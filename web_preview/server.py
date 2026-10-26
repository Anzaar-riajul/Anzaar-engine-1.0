#!/usr/bin/env python3
import http.server
import socketserver
import os
import sys
import socket

PORT = 8080
DIRECTORY = os.path.dirname(os.path.abspath(__file__))

def get_latest_apk():
    repo_root = os.path.abspath(os.path.join(DIRECTORY, ".."))
    search_dirs = [
        os.path.join(repo_root, "dist"),
        os.path.join(repo_root, "Techu Complete Versions", "Android"),
        os.path.join(repo_root, "techuboard_android", "build", "app", "outputs", "flutter-apk"),
        os.path.join(repo_root, "techuboard_android"),
        repo_root,
    ]
    candidate_apks = []
    for d in search_dirs:
        if os.path.isdir(d):
            for entry in os.listdir(d):
                if entry.endswith('.apk'):
                    full_p = os.path.join(d, entry)
                    if os.path.isfile(full_p):
                        try:
                            candidate_apks.append((os.path.getmtime(full_p), full_p, entry))
                        except Exception:
                            pass
    if candidate_apks:
        candidate_apks.sort(key=lambda x: x[0], reverse=True)
        return candidate_apks[0][1], candidate_apks[0][2]
    return None, "Techuboard-Android-Latest.apk"

def get_local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "192.168.10.78"

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        path_only = self.path.split('?')[0]
        query = self.path.split('?')[1] if '?' in self.path else ''
        ua = self.headers.get('User-Agent', '').lower()

        is_mobile_ua = any(m in ua for m in ['mobile', 'android', 'iphone', 'ipod', 'ipad', 'silk', 'harmony'])

        if path_only in ['/apk', '/download-apk', '/Techuboard-Android.apk'] or path_only.endswith('.apk'):
            apk_path, apk_filename = get_latest_apk()
            if apk_path and os.path.exists(apk_path):
                self.send_response(200)
                self.send_header('Content-Type', 'application/vnd.android.package-archive')
                self.send_header('Content-Disposition', f'attachment; filename="{apk_filename}"')
                self.send_header('Content-Length', str(os.path.getsize(apk_path)))
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                with open(apk_path, 'rb') as f:
                    while True:
                        chunk = f.read(65536)
                        if not chunk:
                            break
                        self.wfile.write(chunk)
                return
            else:
                self.send_error(404, "APK not found")
                return

        if path_only in ['/mobile', '/m', '/mobile.html'] or (path_only == '/' and (is_mobile_ua or 'view=mobile' in query)):
            self.path = '/mobile.html'
        elif path_only == '/' and 'view=desktop' in query:
            self.path = '/index.html'

        return super().do_GET()

class ThreadedTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True

def run():
    local_ip = get_local_ip()
    with ThreadedTCPServer(("", PORT), Handler) as httpd:
        print(f"\n========================================================")
        print(f"🚀 Techuboard Multi-Device Web Studio is running live!")
        print(f"💻 Desktop Studio: http://localhost:{PORT}")
        print(f"📱 Phone View URL: http://{local_ip}:{PORT}")
        print(f"========================================================\n")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down server.")
            httpd.shutdown()

if __name__ == '__main__':
    run()
