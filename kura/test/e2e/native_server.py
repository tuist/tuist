"""Lifecycle for isolated native admission tests; never inherit Kura credentials or peers."""
from contextlib import contextmanager
import http.client
import json
import os
from pathlib import Path
import socket
import subprocess
import time
from types import SimpleNamespace


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def stop_process(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def wait_until_ready(process, port):
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError('Kura exited during startup')
        connection = http.client.HTTPConnection('127.0.0.1', port, timeout=1)
        try:
            connection.request('GET', '/ready')
            if connection.getresponse().status == 200:
                return
        except (OSError, http.client.HTTPException):
            pass
        finally:
            connection.close()
        time.sleep(.1)
    raise RuntimeError('Kura did not become ready')


@contextmanager
def native_server(binary, directory, overrides):
    directory = Path(directory).resolve()
    directory.mkdir(parents=True, exist_ok=True)
    if (directory / 'data').exists():
        raise ValueError('use a fresh output directory for an isolated instance')
    port, internal_port = free_port(), free_port()
    while port == internal_port:
        internal_port = free_port()
    env = dict(PATH=os.environ.get('PATH', ''), KURA_PORT=str(port),
               KURA_INTERNAL_PORT=str(internal_port), KURA_TENANT_ID='default',
               KURA_REGION='local', KURA_NODE_URL=f'http://127.0.0.1:{internal_port}',
               KURA_DATA_DIR=str(directory / 'data'), KURA_TMP_DIR=str(directory / 'tmp'),
               KURA_METADATA_STORE_WRITE_BUFFER_BYTES=str(4 * 1024**2),
               KURA_METADATA_STORE_MAX_OPEN_FILES='256', KURA_FILE_DESCRIPTOR_POOL_SIZE='256',
               KURA_OTEL_SERVICE_NAME='admission-test',
               KURA_OTEL_DEPLOYMENT_ENVIRONMENT='local', RUST_LOG='warn')
    env.update(overrides)
    (directory / 'config.json').write_text(json.dumps(env, indent=2))
    with (directory / 'server.log').open('w+') as log:
        process = subprocess.Popen([str(Path(binary).resolve())], env=env, stdout=log, stderr=log)
        try:
            wait_until_ready(process, port)
            yield SimpleNamespace(process=process, port=port, url=f'http://127.0.0.1:{port}')
        except BaseException:
            log.seek(0)
            print(log.read()[-32768:])
            raise
        finally:
            stop_process(process)
