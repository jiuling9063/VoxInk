"""Local-only wire fixture for CloudModelWireTests; no model or account needed."""
from email.parser import BytesParser
from email.policy import default
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # Never log requests, credentials or audio.

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', '0')))
        if '/redirect/' in self.path:
            self.send_response(307)
            self.send_header('Location', '/unexpected-redirect-target')
            self.end_headers()
            return
        if self.headers.get('Authorization') != 'Bearer wire-fixture':
            self.send_error(401)
            return
        try:
            if self.path == '/v1/chat/completions':
                request = json.loads(body)
                assert request['model'] == 'test-model' and request['stream'] is False
                source = json.loads(request['messages'][-1]['content'])['source']
                result = {'choices': [{'finish_reason': 'stop', 'message': {'content': source.rstrip('。') + '。'}}]}
            elif self.path == '/v1/audio/transcriptions':
                message = BytesParser(policy=default).parsebytes(
                    ('Content-Type: ' + self.headers['Content-Type'] + '\r\nMIME-Version: 1.0\r\n\r\n').encode() + body)
                fields = {part.get_param('name', header='content-disposition'): part.get_payload(decode=True) for part in message.iter_parts()}
                assert fields['model'] == b'test-model'
                assert fields['response_format'] == b'json' and fields['language'] == b'en'
                assert fields['file'][:4] == b'RIFF' and fields['file'][8:12] == b'WAVE'
                result = {'text': 'File transcription fixture.'}
            else:
                self.send_error(404)
                return
        except (KeyError, ValueError, AssertionError, TypeError):
            self.send_error(400)
            return
        data = json.dumps(result, ensure_ascii=False).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == '__main__':
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    print(f'http://127.0.0.1:{server.server_port}/v1', flush=True)
    server.serve_forever()
