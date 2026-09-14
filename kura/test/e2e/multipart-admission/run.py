#!/usr/bin/env python3
"""Run the multipart admission ShellSpec against an isolated native Kura server."""
import argparse
import http.client
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def wait_until_ready(process, port):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError('Kura exited during startup')
        connection = http.client.HTTPConnection('127.0.0.1', port, timeout=1)
        try:
            connection.request('GET', '/up')
            if connection.getresponse().status == 200:
                return
        except (OSError, http.client.HTTPException):
            pass
        finally:
            connection.close()
        time.sleep(.1)
    raise RuntimeError('Kura did not become ready')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary')
    parser.add_argument('--shellspec', default='shellspec', help='ShellSpec executable')
    args = parser.parse_args()
    port, internal_port = free_port(), free_port()
    while internal_port == port:
        internal_port = free_port()
    with tempfile.TemporaryDirectory(prefix='kura-multipart-test-') as directory:
        # Keep credentials, enrollment, telemetry endpoints, and peers out of the server.
        env = dict(PATH=os.environ.get('PATH', ''), KURA_PORT=str(port),
                   KURA_INTERNAL_PORT=str(internal_port), KURA_TENANT_ID='default',
                   KURA_REGION='local', KURA_NODE_URL=f'http://127.0.0.1:{internal_port}',
                   KURA_DATA_DIR=directory + '/data', KURA_TMP_DIR=directory + '/tmp',
                   KURA_MEMORY_SOFT_LIMIT_BYTES=str(512 * 1024**2),
                   KURA_MEMORY_HARD_LIMIT_BYTES=str(768 * 1024**2),
                   KURA_METADATA_STORE_READ_CACHE_BYTES=str(16 * 1024**2),
                   KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES=str(16 * 1024**2),
                   KURA_METADATA_STORE_WRITE_BUFFER_BYTES=str(4 * 1024**2),
                   KURA_METADATA_STORE_MAX_OPEN_FILES='256',
                   KURA_FILE_DESCRIPTOR_POOL_SIZE='256',
                   KURA_OTEL_SERVICE_NAME='multipart-admission-test',
                   KURA_OTEL_DEPLOYMENT_ENVIRONMENT='local', RUST_LOG='warn')
        with open(directory + '/kura.log', 'w+') as log:
            process = subprocess.Popen([str(Path(args.binary).resolve())],
                                       env=env, stdout=log, stderr=log)
            try:
                wait_until_ready(process, port)
                subprocess.run([args.shellspec, 'spec/e2e/multipart_admission_spec.sh'],
                               env=dict(os.environ, KURA_MULTIPART_TEST_URL=f'http://127.0.0.1:{port}'),
                               cwd=Path(__file__).resolve().parents[3], check=True)
            except BaseException:
                log.seek(0)
                print(log.read())
                raise
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()


if __name__ == '__main__':
    main()
