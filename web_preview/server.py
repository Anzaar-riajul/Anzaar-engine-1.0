#!/usr/bin/env python3
import http.server
import socketserver
import os
import sys
import socket

PORT = 8080
DIRECTORY = os.path.dirname(os.path.abspath(__file__))

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

        if path_only in ['/apk', '/download-apk', '/Techuboard-Android.apk']:
            apk_path = os.path.abspath(os.path.join(DIRECTORY, "..", "Techu Complete Versions", "Android", "Techuboard-Android-v1.0.apk"))
            if os.path.exists(apk_path):
                self.send_response(200)
                self.send_header('Content-Type', 'application/vnd.android.package-archive')
                self.send_header('Content-Disposition', 'attachment; filename="Techuboard-Android-v1.0.apk"')
                self.send_header('Content-Length', str(os.path.getsize(apk_path)))
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                with open(apk_path, 'rb') as f:
                    self.wfile.write(f.read())
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
