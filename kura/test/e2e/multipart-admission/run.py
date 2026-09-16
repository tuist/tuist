#!/usr/bin/env python3
"""Run the multipart admission ShellSpec against an isolated native Kura server."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from native_server import native_server


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary')
    parser.add_argument('--shellspec', default='shellspec', help='ShellSpec executable')
    args = parser.parse_args()
    overrides = dict(KURA_MEMORY_SOFT_LIMIT_BYTES=str(512 * 1024**2),
                     KURA_MEMORY_HARD_LIMIT_BYTES=str(768 * 1024**2),
                     KURA_METADATA_STORE_READ_CACHE_BYTES=str(16 * 1024**2),
                     KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES=str(16 * 1024**2))
    with tempfile.TemporaryDirectory(prefix='kura-multipart-test-') as directory:
        with native_server(args.binary, directory, overrides) as server:
            subprocess.run([args.shellspec, 'spec/e2e/multipart_admission_spec.sh'],
                           env=dict(os.environ, KURA_MULTIPART_TEST_URL=server.url),
                           cwd=Path(__file__).resolve().parents[3], check=True)


if __name__ == '__main__':
    main()
