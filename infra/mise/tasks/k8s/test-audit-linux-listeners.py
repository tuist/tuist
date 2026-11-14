#!/usr/bin/env python3
"""Run as root on a disposable Linux VM; tests isolate PID, mount and network namespaces."""

import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import unittest


AUDIT = Path(__file__).with_name("audit-linux-listeners.sh").resolve()


def audit(*namespaces, env=None):
    return subprocess.run(
        ["bash", str(AUDIT), *map(str, namespaces)],
        text=True, capture_output=True, timeout=20, env=env,
    )


def listener(protocol, family=socket.AF_INET):
    connection = socket.socket(family, socket.SOCK_STREAM, protocol)
    connection.bind(("::" if family == socket.AF_INET6 else "0.0.0.0", 0))
    connection.listen()
    return connection


class ListenerAuditTests(unittest.TestCase):
    def test_tcp_only_is_not_reported_as_mptcp(self):
        with listener(socket.IPPROTO_TCP) as ipv4, listener(socket.IPPROTO_TCP, socket.AF_INET6) as ipv6:
            result = audit()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(str(ipv4.getsockname()[1]), result.stdout)
            self.assertIn(str(ipv6.getsockname()[1]), result.stdout)
            self.assertNotIn("MPTCP_LISTENER_OBSERVED", result.stdout)

    def test_host_mptcp_is_reported_once(self):
        with listener(262) as connection:
            result = audit()
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn(str(connection.getsockname()[1]), result.stdout)
            self.assertEqual(result.stdout.count("MPTCP_LISTENER_OBSERVED"), 1)

    def test_process_network_namespace_is_not_missed(self):
        enabled = Path("/proc/sys/net/mptcp/enabled")
        original = enabled.read_text()
        enabled.write_text("0\n")
        child = subprocess.Popen(
            ["unshare", "--net", sys.executable, "-u", "-c",
             "import socket,sys; s=socket.socket(2,1,262); s.bind(('0.0.0.0',0)); "
             "s.listen(); print(s.getsockname()[1]); sys.stdin.read()"],
            text=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        )
        try:
            port = child.stdout.readline().strip()
            self.assertTrue(port, "namespace listener failed to start")
            result = audit()
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn(port, result.stdout)
        finally:
            child.communicate(timeout=5)
            enabled.write_text(original)
            self.assertEqual(child.returncode, 0)

    def test_pinned_namespace_and_existing_listener_survive_disabled_sysctl(self):
        subprocess.run(["ip", "netns", "add", "audit-test"], check=True)
        original = os.open("/proc/self/ns/net", os.O_RDONLY)
        target = os.open("/run/netns/audit-test", os.O_RDONLY)
        connection = None
        try:
            os.setns(target, os.CLONE_NEWNET)
            connection = listener(262)
            Path("/proc/sys/net/mptcp/enabled").write_text("0\n")
            os.setns(original, os.CLONE_NEWNET)
            # No process resides in the target namespace; only its pin and socket remain.
            result = audit()
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn(str(connection.getsockname()[1]), result.stdout)
            self.assertIn("/run/netns/audit-test", result.stdout)
        finally:
            os.setns(original, os.CLONE_NEWNET)
            if connection is not None:
                connection.close()
            os.close(target)
            os.close(original)
            subprocess.run(["ip", "netns", "delete", "audit-test"], check=True)

    def test_missing_namespace_is_incomplete_even_with_observed_mptcp(self):
        with listener(262):
            result = audit("/no-such-network-namespace")
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertIn("INCOMPLETE", result.stderr)
            self.assertIn("MPTCP_LISTENER_OBSERVED", result.stdout)

    def test_diagnostic_failure_is_never_a_negative_result(self):
        with tempfile.TemporaryDirectory() as directory:
            fake_ss = Path(directory, "ss")
            for status in (0, 1):
                with self.subTest(status=status):
                    fake_ss.write_text(f"#!/bin/sh\necho 'diagnostics unavailable' >&2\nexit {status}\n")
                    fake_ss.chmod(0o755)
                    result = audit(env={**os.environ, "PATH": directory + ":" + os.environ["PATH"]})
                    self.assertEqual(result.returncode, 2, result.stderr)
                    self.assertNotIn("No MPTCP listeners observed", result.stdout)


if __name__ == "__main__":
    if sys.platform != "linux" or os.geteuid() != 0:
        sys.exit("Run as root on a disposable Linux VM with MPTCP, iproute2 and util-linux.")
    if sys.argv[1:] != ["--isolated"] or os.getpid() != 1:
        sys.exit(subprocess.call([
            "unshare", "--mount", "--pid", "--fork", "--mount-proc", "--net",
            sys.executable, str(Path(__file__).resolve()), "--isolated",
        ]))
    # All mounts, sockets, sysctls and pinned namespaces below stay inside the sandbox.
    subprocess.run(["mount", "-t", "tmpfs", "-o", "mode=0700", "tmpfs", "/run"], check=True)
    unittest.main(argv=[sys.argv[0]], verbosity=2)
