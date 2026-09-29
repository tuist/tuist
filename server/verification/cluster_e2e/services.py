import http.server, http.client, threading, socket, struct, os, itertools
counter = itertools.count()
addresses = ['127.0.0.1', os.environ['TUIST_E2E_SECOND_ADDRESS']]

def dns():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(('127.0.0.1', 15353))
    while True:
        (data, client) = s.recvfrom(4096)
        i = 12
        while data[i]:
            i += data[i] + 1
        end = i + 5
        qtype = struct.unpack('!H', data[i + 1:i + 3])[0]
        records = addresses if qtype == 1 else []
        reply = data[:2] + struct.pack('!HHHHH', 33152, 1, len(records), 0, 0) + data[12:end]
        for address in records:
            reply += b'\xc0\x0c' + struct.pack('!HHIH', 1, 1, 1, 4) + socket.inet_aton(address)
        s.sendto(reply, client)

class Proxy(http.server.BaseHTTPRequestHandler):

    def handle_request(self):
        body = self.rfile.read(int(self.headers.get('content-length', 0)))
        start = next(counter) % 2
        for index in [start, 1 - start]:
            connection = http.client.HTTPConnection('127.0.0.1', 14101 + index, timeout=90)
            try:
                connection.request(self.command, self.path, body, {k: v for (k, v) in self.headers.items() if k.lower() not in ['host', 'connection', 'content-length']})
                response = connection.getresponse()
                content = response.read()
                self.send_response(response.status)
                for (key, value) in response.getheaders():
                    if key.lower() not in ['connection', 'transfer-encoding', 'content-length']:
                        self.send_header(key.replace('\r', '').replace('\n', '').replace(':', ''), value.replace('\r', '').replace('\n', ''))
                self.send_header('x-verification-backend', str(index + 1))
                self.send_header('content-length', str(len(content)))
                self.end_headers()
                self.wfile.write(content)
                connection.close()
                return
            except (OSError, http.client.HTTPException):
                connection.close()
        self.send_error(503, 'Both verification servers unavailable')
    do_GET = handle_request
    do_POST = handle_request
    do_DELETE = handle_request

    def log_message(self, *args):
        pass
threading.Thread(target=dns, daemon=True).start()
print('Local discovery and round-robin proxy ready', flush=True)
http.server.ThreadingHTTPServer.request_queue_size = 128
http.server.ThreadingHTTPServer(('127.0.0.1', 14100), Proxy).serve_forever()
