"""Run paced ByteStream bursts against an isolated native Kura and retain metrics."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.request

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from native_server import native_server, stop_process


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary')
    parser.add_argument('client')
    parser.add_argument('out')
    parser.add_argument('--requests', type=int, default=128)
    parser.add_argument('--concurrency', type=int, default=32)
    parser.add_argument('--connections', type=int, default=1)
    parser.add_argument('--profile', choices=['small', 'ci-small', 'pro-floor'], default='small')
    args = parser.parse_args()
    if min(args.requests, args.concurrency, args.connections) < 1:
        parser.error('requests, concurrency, and connections must be positive')
    client, out = str(Path(args.client).resolve()), Path(args.out).resolve()
    soft, hard, block, writes, manifest, snapshot = (64, 96, 4, 8, 4, 4)
    if args.profile == 'ci-small':
        soft, hard = 512, 544
    if args.profile == 'pro-floor':
        soft, hard, block, writes, manifest, snapshot = (1843, 2611, 32, 32, 32, 64)
    overrides = {key: str(value * 1024**2) for key, value in [
        ('KURA_MEMORY_SOFT_LIMIT_BYTES', soft), ('KURA_MEMORY_HARD_LIMIT_BYTES', hard),
        ('KURA_METADATA_STORE_READ_CACHE_BYTES', block),
        ('KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES', writes),
        ('KURA_MANIFEST_CACHE_MAX_BYTES', manifest), ('KURA_SNAPSHOT_CACHE_MAX_BYTES', snapshot)]}
    if args.profile == 'pro-floor':
        overrides['KURA_MEMORY_FLOOR_BYTES'] = str(512 * 1024**2)
    samples = []
    with native_server(args.binary, out, overrides) as server:
        def sample(phase):
            with urllib.request.urlopen(server.url + '/metrics', timeout=3) as response:
                text = response.read().decode()
            filename = f'{len(samples):04d}-{phase}.metrics'
            (out / filename).write_text(text)
            cpu = subprocess.check_output(['/bin/ps', '-p', str(server.process.pid), '-o', 'time='], text=True).strip()
            samples.append(dict(t=time.time(), phase=phase, file=filename, cpu=cpu))

        def run_load(operation, requests, concurrency, pace=0):
            loadenv = dict(os.environ, LOAD_TARGET=f'127.0.0.1:{server.port}', LOAD_OPERATION=operation,
                           LOAD_REQUESTS=str(requests), LOAD_KEYSPACE='1', LOAD_CONCURRENCY=str(concurrency),
                           LOAD_CONNECTIONS=str(args.connections if operation == 'read' else 1),
                           LOAD_SIZE_KB='1024', LOAD_READ_BYTES_PER_SECOND=str(pace), LOAD_STREAM_WINDOW_BYTES='65536',
                           LOAD_MIN_REQUEST_MS='500' if operation == 'read' else '0')
            with (out / f'{operation}.log').open('w') as log:
                process = subprocess.Popen([client, 'load'], env=loadenv, stdout=log, stderr=subprocess.STDOUT)
                try:
                    while process.poll() is None:
                        sample(operation)
                        time.sleep(.2)
                    return process.returncode
                finally:
                    stop_process(process)

        if run_load('write', 1, 1) != 0:
            raise RuntimeError((out / 'write.log').read_text())
        for _ in range(25):
            sample('idle')
            time.sleep(.2)
        result = run_load('read', args.requests, args.concurrency, 2 * 1024**2)
        for _ in range(75):
            sample('settled')
            time.sleep(.2)
        (out / 'samples.json').write_text(json.dumps(samples))
        with (out / 'disk.txt').open('w') as disk:
            subprocess.run(['/usr/bin/du', '-sk', str(out / 'data')], stdout=disk, check=True)
        print((out / 'read.log').read_text())
        print('read_exit', result, 'output', out)
    return result


if __name__ == '__main__':
    sys.exit(main())
