import subprocess, http.server, socketserver, os, time, threading
from urllib.parse import urlparse, parse_qs
from evdev import UInput, AbsInfo, ecodes as e

ENV = dict(os.environ, XDG_RUNTIME_DIR=f'/run/user/{os.getuid()}', WAYLAND_DISPLAY=os.environ.get('WAYLAND_DISPLAY', 'wayland-0'))

FRAME = b''
LAST = 0
def cap():
    global FRAME
    while True:
        if time.time() - LAST > 5:
            time.sleep(0.2); continue
        try:
            f = subprocess.run(['grim', '-t', 'png', '-l', '1', '-'], env=ENV,
                               capture_output=True, timeout=5).stdout
            if f: FRAME = f
        except Exception:
            pass
        time.sleep(0.1)
threading.Thread(target=cap, daemon=True).start()

M = 4095
ui = UInput({
    e.EV_KEY: [e.BTN_TOUCH],
    e.EV_ABS: [
        (e.ABS_X, AbsInfo(0, 0, M, 0, 0, 0)),
        (e.ABS_Y, AbsInfo(0, 0, M, 0, 0, 0)),
        (e.ABS_MT_SLOT, AbsInfo(0, 0, 0, 0, 0, 0)),
        (e.ABS_MT_TRACKING_ID, AbsInfo(0, 0, 65535, 0, 0, 0)),
        (e.ABS_MT_POSITION_X, AbsInfo(0, 0, M, 0, 0, 0)),
        (e.ABS_MT_POSITION_Y, AbsInfo(0, 0, M, 0, 0, 0)),
    ]}, name='web-touch')

lock = threading.Lock()

def touch(points, ms):
    # points contains (fx, fy) pairs in the 0..1 range; ms is the total duration
    with lock:
        def pos(fx, fy):
            x = int(max(0.0, min(1.0, fx)) * M); y = int(max(0.0, min(1.0, fy)) * M)
            ui.write(e.EV_ABS, e.ABS_MT_POSITION_X, x)
            ui.write(e.EV_ABS, e.ABS_MT_POSITION_Y, y)
            ui.write(e.EV_ABS, e.ABS_X, x)
            ui.write(e.EV_ABS, e.ABS_Y, y)
            ui.syn()
        ui.write(e.EV_ABS, e.ABS_MT_SLOT, 0)
        ui.write(e.EV_ABS, e.ABS_MT_TRACKING_ID, 1)
        ui.write(e.EV_KEY, e.BTN_TOUCH, 1)
        pos(*points[0])
        step = ms / 1000.0 / max(1, len(points) - 1)
        for p in points[1:]:
            time.sleep(step); pos(*p)
        if len(points) == 1:
            time.sleep(0.08)
        ui.write(e.EV_ABS, e.ABS_MT_TRACKING_ID, -1)
        ui.write(e.EV_KEY, e.BTN_TOUCH, 0)
        ui.syn()

def tap(fx, fy):
    touch([(fx, fy)], 80)

def swipe(x1, y1, x2, y2, ms):
    n = 12
    touch([(x1 + (x2 - x1) * k / n, y1 + (y2 - y1) * k / n) for k in range(n + 1)], ms)

PAGE = b'''<body style="margin:0;background:#000;overflow:hidden"><img id=i style="touch-action:none;width:100vw;height:100vh;object-fit:contain;cursor:pointer"><script>
var T,busy=0;
function r(){if(busy)return;busy=1;var n=new Image();n.onload=function(){i.src=n.src;busy=0;T=setTimeout(r,250)};n.onerror=function(){busy=0;T=setTimeout(r,2000)};n.src="/s.png?"+Date.now()}
r();
function later(){clearTimeout(T);T=setTimeout(r,150)}
function P(ev){var W=innerWidth,H=innerHeight,nw=i.naturalWidth,nh=i.naturalHeight;if(!nw)return null;
 var s=Math.min(W/nw,H/nh),w=nw*s,h=nh*s,ox=(W-w)/2,oy=(H-h)/2;
 return [Math.max(0,Math.min(1,(ev.clientX-ox)/w)),Math.max(0,Math.min(1,(ev.clientY-oy)/h))]}
var d=null;
i.onpointerdown=function(ev){var a=P(ev);if(!a)return;d=[a,Date.now(),ev.clientX,ev.clientY];i.setPointerCapture(ev.pointerId);ev.preventDefault()};
i.onpointerup=function(ev){if(!d)return;var a=d[0],e=P(ev),ms=Math.min(1000,Math.max(120,Date.now()-d[1])),mv=Math.hypot(ev.clientX-d[2],ev.clientY-d[3]);d=null;if(!e)return;
 fetch(mv<10?"/tap?x="+a[0]+"&y="+a[1]:"/swipe?x1="+a[0]+"&y1="+a[1]+"&x2="+e[0]+"&y2="+e[1]+"&ms="+ms).then(later)};
i.onpointercancel=function(){d=null};
</script>'''

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(s):
        global LAST
        try:
            u = urlparse(s.path); q = parse_qs(u.query)
            if u.path == '/s.png':
                LAST = time.time()
                for _ in range(30):
                    if FRAME: break
                    time.sleep(0.1)
                d, t = FRAME, 'image/png'
            elif u.path == '/tap':
                tap(float(q['x'][0]), float(q['y'][0])); d, t = b'ok', 'text/plain'
            elif u.path == '/swipe':
                swipe(float(q['x1'][0]), float(q['y1'][0]), float(q['x2'][0]), float(q['y2'][0]), int(q['ms'][0]))
                d, t = b'ok', 'text/plain'
            else:
                d, t = PAGE, 'text/html'
            s.send_response(200); s.send_header('Content-Type', t)
            s.send_header('Content-Length', str(len(d))); s.end_headers(); s.wfile.write(d)
        except Exception:
            pass
    def log_message(*a): pass

socketserver.TCPServer.allow_reuse_address = True
socketserver.ThreadingTCPServer(('0.0.0.0', 8085), H).serve_forever()
