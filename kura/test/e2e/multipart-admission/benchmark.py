#!/usr/bin/env python3
"""Run two waves of real multipart uploads against an isolated local Kura binary."""
import argparse
import asyncio
import collections
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import urllib.parse


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


async def request(port, path, body=b'', method='POST', content_type='application/octet-stream'):
    reader, writer = await asyncio.wait_for(asyncio.open_connection('127.0.0.1', port), 5)
    try:
        writer.write((f'{method} {path} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n'
                      f'Content-Length: {len(body)}\r\nContent-Type: {content_type}\r\n\r\n').encode())
        writer.write(body)
        await writer.drain()
        header = await asyncio.wait_for(reader.readuntil(b'\r\n\r\n'), 10)
        content = await asyncio.wait_for(reader.read(), 10)
        return int(header.split(b' ', 2)[1]), content
    finally:
        writer.close()
        await writer.wait_closed()


def start_path(key):
    return '/api/cache/module/start?' + urllib.parse.urlencode(dict(
        tenant_id='default', namespace_id='benchmark', hash=key, name='Module', cache_category='builds'))


async def part(port, upload_id, payload):
    status, body = await request(port, f'/api/cache/module/part?upload_id={upload_id}&part_number=1', payload)
    if status != 204:
        raise RuntimeError(f'part failed: {status}: {body!r}')


async def complete(port, upload_id):
    status, body = await request(port, f'/api/cache/module/complete?upload_id={upload_id}',
                                 b'{"parts":[1]}', content_type='application/json')
    if status != 204:
        raise RuntimeError(f'complete failed: {status}: {body!r}')


async def run(args, directory, log):
    port, internal_port = free_port(), free_port()
    while internal_port == port:
        internal_port = free_port()
    # Do not inherit credentials, enrollment, telemetry, or peer configuration.
    env = dict(PATH=os.environ.get('PATH', ''), KURA_PORT=str(port),
               KURA_INTERNAL_PORT=str(internal_port), KURA_TENANT_ID='default',
               KURA_REGION='local', KURA_NODE_URL=f'http://127.0.0.1:{internal_port}',
               KURA_DATA_DIR=directory + '/data', KURA_TMP_DIR=directory + '/tmp',
               KURA_MEMORY_SOFT_LIMIT_BYTES=str(512 * 1024**2),
               KURA_MEMORY_HARD_LIMIT_BYTES=str((512 + args.headroom_mib) * 1024**2),
               KURA_METADATA_STORE_READ_CACHE_BYTES=str(16 * 1024**2),
               KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES=str(16 * 1024**2),
               KURA_METADATA_STORE_WRITE_BUFFER_BYTES=str(4 * 1024**2),
               KURA_METADATA_STORE_MAX_OPEN_FILES='256',
               KURA_FILE_DESCRIPTOR_POOL_SIZE='256', KURA_OTEL_SERVICE_NAME='multipart-benchmark',
               KURA_OTEL_DEPLOYMENT_ENVIRONMENT='local', RUST_LOG='warn')
    if args.fixed_limit:
        env['KURA_MULTIPART_MAX_ACTIVE_UPLOADS'] = str(args.fixed_limit)
    process = subprocess.Popen([str(Path(args.binary).resolve())], env=env, stdout=log, stderr=log)
    stop = asyncio.Event()
    rss_kib, probe_latencies = [], []
    memory_peaks = collections.Counter()
    payload = b'x' * (args.payload_kib * 1024)

    async def sample_rss():
        while not stop.is_set():
            sample = await asyncio.create_subprocess_exec('ps', '-o', 'rss=', '-p', str(process.pid),
                                                         stdout=asyncio.subprocess.PIPE)
            output, _ = await sample.communicate()
            if output.strip():
                rss_kib.append(int(output.strip()))
            before = time.monotonic()
            status, data = await request(port, start_path('probe').replace('/start?', '/artifact?'), method='GET')
            if status != 200 or data != payload:
                raise RuntimeError('ordinary read failed during upload contention')
            probe_latencies.append((time.monotonic() - before) * 1000)
            status, data = await request(port, '/metrics', method='GET')
            if status != 200:
                raise RuntimeError('metrics request failed')
            for line in data.decode().splitlines():
                fields = line.split()
                if len(fields) == 2 and fields[0] in (
                        'kura_jemalloc_allocated_bytes', 'kura_jemalloc_resident_bytes',
                        'kura_memory_transient_reserved_bytes', 'kura_memory_elastic_transient_reserved_bytes'):
                    memory_peaks[fields[0]] = max(memory_peaks[fields[0]], float(fields[1]))
            await asyncio.sleep(.1)

    sampler = None
    try:
        for _ in range(100):
            if process.poll() is not None:
                raise RuntimeError('Kura exited during startup')
            try:
                if (await request(port, '/up', method='GET'))[0] == 200:
                    break
            except (OSError, asyncio.IncompleteReadError):
                pass
            await asyncio.sleep(.1)
        else:
            raise RuntimeError('Kura did not become ready')
        if args.shellspec:
            suite_env = dict(os.environ, KURA_MULTIPART_TEST_URL=f'http://127.0.0.1:{port}')
            suite = await asyncio.create_subprocess_exec(args.shellspec,
                'spec/e2e/multipart_admission_spec.sh', env=suite_env,
                cwd=str(Path(__file__).resolve().parents[3]))
            code = await suite.wait()
            if code:
                raise RuntimeError(f'ShellSpec failed: {code}')
            return dict(shellspec='passed', capacity=args.headroom_mib)
        status, body = await request(port, start_path('probe'))
        if status != 200:
            raise RuntimeError('probe upload start failed')
        probe_id = json.loads(body)['upload_id']
        await part(port, probe_id, payload)
        await complete(port, probe_id)
        sampler = asyncio.create_task(sample_rss())
        statuses, latencies, reads, finished = collections.Counter(), [], 0, 0
        capacity = args.fixed_limit or args.headroom_mib
        begun = time.monotonic()
        for iteration in range(args.rounds):
            first = []
            # Fully occupy the slots, with real parts already staged.
            for index in range(capacity):
                status, body = await request(port, start_path(f'{iteration}-seed-{index}'))
                if status != 200:
                    raise RuntimeError(f'seed start failed: {status}: {body!r}')
                upload_id = json.loads(body)['upload_id']
                await part(port, upload_id, payload)
                first.append(upload_id)

            async def next_upload(index):
                key = f'{iteration}-next-{index}'
                before = time.monotonic()
                status, body = await request(port, start_path(key))
                latencies.append((time.monotonic() - before) * 1000)
                statuses[status] += 1
                if status != 200:
                    if status != 429:
                        raise RuntimeError(f'unexpected start status: {status}: {body!r}')
                    return 0
                upload_id = json.loads(body)['upload_id']
                await part(port, upload_id, payload)
                await complete(port, upload_id)
                path = start_path(key).replace('/start?', '/artifact?')
                read_status, data = await request(port, path, method='GET')
                if read_status != 200 or data != payload:
                    raise RuntimeError(f'artifact round trip failed: {read_status}, {len(data)} bytes')
                return 1

            async def release_first_wave():
                await asyncio.sleep(args.hold_ms / 1000)
                await asyncio.gather(*(complete(port, upload_id) for upload_id in first))

            results = await asyncio.gather(release_first_wave(), *(next_upload(i) for i in range(args.burst)))
            reads += sum(results[1:])
            finished += capacity + sum(results[1:])
        stop.set()
        await sampler
        latencies.sort()
        probe_latencies.sort()
        return dict(binary=args.binary, capacity=capacity, headroom_mib=args.headroom_mib,
                    burst=args.burst, rounds=args.rounds, hold_ms=args.hold_ms,
                    payload_kib=args.payload_kib, start_statuses=dict(statuses),
                    start_p50_ms=round(latencies[int(.50 * (len(latencies) - 1))], 2),
                    start_p99_ms=round(latencies[int(.99 * (len(latencies) - 1))], 2),
                    completed=finished, verified_downloads=reads,
                    ordinary_reads=len(probe_latencies),
                    ordinary_read_p99_ms=round(probe_latencies[int(.99 * (len(probe_latencies) - 1))], 2),
                    peak_memory_mib={name: round(value / 1024**2, 2) for name, value in memory_peaks.items()},
                    peak_rss_mib=round(max(rss_kib, default=0) / 1024, 2),
                    elapsed_seconds=round(time.monotonic() - begun, 2))
    finally:
        stop.set()
        if sampler and not sampler.done():
            sampler.cancel()
            await asyncio.gather(sampler, return_exceptions=True)
        if process.poll() is None:
            process.terminate()
            try:
                await asyncio.to_thread(process.wait, 10)
            except subprocess.TimeoutExpired:
                process.kill()
                await asyncio.to_thread(process.wait)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary')
    parser.add_argument('--shellspec', help='Run the multipart ShellSpec using this executable and the isolated native server')
    parser.add_argument('--headroom-mib', type=int, default=128)
    parser.add_argument('--fixed-limit', type=int)
    parser.add_argument('--burst', type=int, default=128)
    parser.add_argument('--rounds', type=int, default=3)
    parser.add_argument('--hold-ms', type=int, default=200)
    parser.add_argument('--payload-kib', type=int, default=64)
    args = parser.parse_args()
    if args.shellspec and (args.headroom_mib != 256 or args.fixed_limit):
        parser.error('--shellspec requires --headroom-mib 256 and no fixed override')
    for name, value in vars(args).items():
        if isinstance(value, int) and value <= 0:
            parser.error(f'{name} must be positive')
    with tempfile.TemporaryDirectory(prefix='kura-multipart-benchmark-') as directory:
        with open(directory + '/kura.log', 'w+') as log:
            try:
                print(json.dumps(asyncio.run(run(args, directory, log)), indent=2))
            except Exception:
                log.seek(0)
                print(log.read())
                raise


if __name__ == '__main__':
    main()
