import sys

class AFCRestorePatch:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.printer.register_event_handler("klippy:connect", self._patch)

    def _patch(self):
        afc = self.printer.lookup_object('AFC')
        orig = afc.restore_pos
        mod = sys.modules[type(afc).__module__]

        def restore_pos(move_z_first=True, keep_offsets=False):
            if keep_offsets and not move_z_first:
                gm = afc.gcode_move
                gm.absolute_coord = afc.absolute_coord
                mod.set_gcode_absolute_extrude(gm, afc.absolute_extrude)
                gm.extrude_factor = afc.extrude_factor
                gm.speed = afc.speed
                gm.speed_factor = afc.speed_factor
                afc.position_saved = False
                return
            return orig(move_z_first=move_z_first, keep_offsets=keep_offsets)

        afc.restore_pos = restore_pos

def load_config(config):
    return AFCRestorePatch(config)
