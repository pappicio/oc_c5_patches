import logging
import types


def _pickup(self, gcmd, tool, raise_z=True):
    x, y = self.docks[tool]
    clear_feed = self.clear_travel_speed * 60.
    self._apply_offsets(tool)

    if raise_z:
        self._raise_z()

    self._move(x=self.approach_x, feed=clear_feed)
    self._move(y=y, feed=clear_feed)
    self._move(x=self.pre_dock_x,
               feed=self.pickup_predock_speed * 60.)
    self._move(x=x, feed=self.pickup_latch_speed * 60.)

    self._run('M400')

    if not self._button(self.grab_buttons[tool], gcmd):
        raise gcmd.error(
            'T%d grab sensor did not engage at mount' % tool
        )

    self._run('MOTOR_GRAB')

    slow_distance = min(self.pullback, self.pullback_slow_distance)

    self._move(x=x - slow_distance,
               feed=self.pullback_speed * 60.)

    if x - self.approach_x > slow_distance:
        self._move(x=self.approach_x, feed=clear_feed)

    self._run('MOTOR_GRAB2')
    self._pause_ms(self.pickup_latch_wait_ms)
    self._verify(gcmd, tool)

    extruder = 'extruder' if tool == 0 else 'extruder%d' % tool

    self._run('ACTIVATE_EXTRUDER EXTRUDER=%s' % extruder)
    self._restore_pressure_advance(extruder)

    if abs(self.printer.lookup_object('toolhead').get_position()[0]
           - self.approach_x) > 1.5:
        self._move(x=self.approach_x,
                   feed=self.pickup_departure_speed * 60.)


def _home_for_print(self, gcmd):

    dock, grab, attached = self._preflight(gcmd, axes='')
    recovered = attached is not None

    if attached is not None:
        self.cmd_recover_attached(gcmd)
        dock, grab, attached = self._preflight(gcmd, axes='')

    if attached is not None:
        raise gcmd.error(
            'Attached head remains after recovery; Z homing blocked'
        )

    if not all(dock):
        raise gcmd.error(
            'Confirm all heads are docked before print homing'
        )

    toolhead = self.printer.lookup_object('toolhead')
    eventtime = self.printer.get_reactor().monotonic()
    homed_axes = toolhead.get_status(eventtime).get('homed_axes', '')

    if recovered or ('x' in homed_axes and 'y' in homed_axes):
        logging.info(
            "C5 HOME_FOR_PRINT: X/Y already homed, executing G28 Z"
        )
        self._run('G28 Z')

    else:
        logging.info(
            "C5 HOME_FOR_PRINT: X/Y not homed, executing full G28"
        )

        old_passthrough = self._g28_passthrough
        self._g28_passthrough = True

        try:
            self._run('G28')
        finally:
            self._g28_passthrough = old_passthrough


class C5PickupPatch:

    def __init__(self, config):
        self.printer = config.get_printer()
        self.printer.register_event_handler(
            "klippy:connect", self._patch
        )

    def _patch(self):

        tc = self.printer.lookup_object('creator5_toolchanger')

        # Pickup runtime patch
        tc._pickup = types.MethodType(_pickup, tc)

        # Home for print runtime patch
        tc.cmd_home_for_print = types.MethodType(
            _home_for_print, tc
        )

        # Update the already registered G-code callback
        gcode = self.printer.lookup_object('gcode')
        desc = gcode.gcode_help.get('C5_HOME_FOR_PRINT')

        gcode.register_command('C5_HOME_FOR_PRINT', None)

        gcode.register_command(
            'C5_HOME_FOR_PRINT',
            tc.cmd_home_for_print,
            desc=desc
        )

        logging.info(
            "C5 runtime patches applied: pickup and home_for_print"
        )


def load_config(config):
    return C5PickupPatch(config)
