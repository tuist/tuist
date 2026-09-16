"""Run paced ByteStream bursts against an isolated native Kura and retain metrics."""
import argparse
import json
import os
import pathlib
import socket
import subprocess
import sys
import time
import urllib.request
import urllib.error

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('binary')
parser.add_argument('client')
parser.add_argument('out')
parser.add_argument('--requests', type=int, default=128)
args = parser.parse_args()
if args.requests < 1:
    parser.error('--requests must be positive')
binary, client, out = str(pathlib.Path(args.binary).resolve()), str(pathlib.Path(args.client).resolve()), args.out
out = pathlib.Path(out).resolve()
out.mkdir(parents=True, exist_ok=True)
if (out / 'data').exists():
    parser.error('use a fresh output directory for an isolated instance')
def port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]
p, internal = port(), port()
while internal == p:
    internal = port()
env = dict(PATH=os.environ['PATH'], KURA_PORT=str(p), KURA_INTERNAL_PORT=str(internal),
           KURA_NODE_URL=f'http://127.0.0.1:{internal}', KURA_TENANT_ID='default',
           KURA_REGION='local', KURA_DATA_DIR=str(out/'data'), KURA_TMP_DIR=str(out/'tmp'),
           KURA_MEMORY_SOFT_LIMIT_BYTES=str(64*1024**2), KURA_MEMORY_HARD_LIMIT_BYTES=str(96*1024**2),
           KURA_METADATA_STORE_READ_CACHE_BYTES=str(4*1024**2),
           KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES=str(8*1024**2),
           KURA_METADATA_STORE_WRITE_BUFFER_BYTES=str(4*1024**2),
           KURA_MANIFEST_CACHE_MAX_BYTES=str(4*1024**2), KURA_SNAPSHOT_CACHE_MAX_BYTES=str(4*1024**2),
           KURA_METADATA_STORE_MAX_OPEN_FILES='256', KURA_FILE_DESCRIPTOR_POOL_SIZE='256',
           KURA_OTEL_SERVICE_NAME='bytestream-bench', KURA_OTEL_DEPLOYMENT_ENVIRONMENT='local',
           RUST_LOG='warn')
server = subprocess.Popen([binary], env=env, stdout=open(out/'server.log','w'), stderr=subprocess.STDOUT)
def scrape():
    return urllib.request.urlopen(f'http://127.0.0.1:{p}/metrics', timeout=3).read().decode()
samples = []
def sample(phase):
    text = scrape()
    filename = f'{len(samples):04d}-{phase}.metrics'
    (out/filename).write_text(text)
    cpu = subprocess.check_output(['/bin/ps','-p',str(server.pid),'-o','time='], text=True).strip()
    samples.append(dict(t=time.time(), phase=phase, file=filename, cpu=cpu))
def run_load(operation, requests, concurrency, pace=0):
    loadenv = dict(os.environ, LOAD_TARGET=f'127.0.0.1:{p}', LOAD_OPERATION=operation,
                   LOAD_REQUESTS=str(requests), LOAD_KEYSPACE='1', LOAD_CONCURRENCY=str(concurrency),
                   LOAD_SIZE_KB='1024', LOAD_READ_BYTES_PER_SECOND=str(pace), LOAD_STREAM_WINDOW_BYTES='65536', LOAD_MIN_REQUEST_MS='500' if operation=='read' else '0')
    with open(out / f'{operation}.log', 'w') as log:
        proc = subprocess.Popen([client, 'load'], env=loadenv, stdout=log, stderr=subprocess.STDOUT)
        try:
            while proc.poll() is None:
                sample(operation)
                time.sleep(.2)
            return proc.returncode
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()
try:
    for i in range(200):
        if server.poll() is not None:
            raise RuntimeError((out/'server.log').read_text())
        try:
            if urllib.request.urlopen(f'http://127.0.0.1:{p}/ready', timeout=1).status == 200:
                break
        except (OSError, urllib.error.URLError):
            time.sleep(.1)
    else:
        raise RuntimeError('not ready')
    assert run_load('write',1,1)==0, (out/'write.log').read_text()
    for _ in range(25):
        sample('idle')
        time.sleep(.2)
    result = run_load('read',args.requests,32,2*1024**2)
    for _ in range(75):
        sample('settled')
        time.sleep(.2)
    (out/'samples.json').write_text(json.dumps(samples))
    subprocess.run(['/usr/bin/du','-sk',str(out/'data')],stdout=open(out/'disk.txt','w'))
    print((out/'read.log').read_text())
    print('read_exit',result,'output',out)
    sys.exit(result)
finally:
    server.terminate()
    try:
        server.wait(timeout=10)
    except subprocess.TimeoutExpired:
        server.kill()
        server.wait()
