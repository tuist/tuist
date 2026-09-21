"""Drive one switch's CLI over SSH.

Three properties of this firmware shape the whole module:

- its SSH server negotiates only `diffie-hellman-group14-sha1` and `ssh-rsa`,
  which a current OpenSSH refuses by default. The failure reads like an
  unreachable host, not like a rejected algorithm.
- it allows one authentication attempt per connection and closes on the first
  key the client offers, so the agent must be taken out of the loop.
- its session table holds a handful of sessions and does not reap the ones a
  client abandons. `exit` from privileged mode drops to user EXEC and keeps the
  session; only `logout` ends it. Leaking sessions locks every operator, and
  this session's own tooling, out of the switch until it is power-cycled, with
  the data plane still forwarding so nothing looks wrong. Hence: one session per
  run, and a logout that runs even when the work raised.
"""

import os
import queue
import re
import subprocess
import threading
import time

PAGER = re.compile(r"Press any key to continue \(Q to quit\)")
PROMPT = re.compile(r"[\w.-]+[#>]\s*$")
PASSWORD = re.compile(r"[Pp]assword:")

CONNECT_TIMEOUT = 10
COMMAND_TIMEOUT = 120
QUIET_PERIOD = 0.6


class SwitchError(RuntimeError):
    pass


class Session:
    def __init__(self, address, username, key_path, verbose=False):
        self.address = address
        self.username = username
        self.key_path = os.path.expanduser(key_path)
        self.verbose = verbose
        self.proc = None
        self.transcript = []
        self._queue = queue.Queue()

    def _ssh_command(self):
        return [
            "ssh", "-tt",
            "-i", self.key_path,
            "-o", "IdentitiesOnly=yes",
            "-o", "IdentityAgent=none",
            "-o", "KexAlgorithms=+diffie-hellman-group14-sha1",
            "-o", "HostKeyAlgorithms=+ssh-rsa",
            "-o", "PubkeyAcceptedAlgorithms=+ssh-rsa",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "BatchMode=yes",
            "-o", f"ConnectTimeout={CONNECT_TIMEOUT}",
            f"{self.username}@{self.address}",
        ]

    def __enter__(self):
        self.proc = subprocess.Popen(
            self._ssh_command(),
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, bufsize=0,
        )
        threading.Thread(target=self._read_forever, daemon=True).start()
        self._drain(6)
        if self.proc.poll() is not None:
            raise SwitchError(
                f"{self.address} accepted no session: {self.full_transcript().strip() or 'no output'}\n"
                f"If it answers ping but not SSH, its session table is wedged; the web UI still "
                f"works and a reboot clears it."
            )
        self.run("enable")
        return self

    def __exit__(self, *exc):
        try:
            self._logout()
        finally:
            if self.proc and self.proc.poll() is None:
                try:
                    self.proc.terminate()
                    self.proc.wait(timeout=5)
                except Exception:
                    self.proc.kill()
        return False

    def _read_forever(self):
        while True:
            chunk = self.proc.stdout.read(1)
            if not chunk:
                self._queue.put(None)
                return
            self._queue.put(chunk)

    def _write(self, text):
        self.proc.stdin.write(text.encode())
        self.proc.stdin.flush()

    def _drain(self, timeout):
        """Read until the prompt has been quiet for QUIET_PERIOD, or time is up."""
        buffer = ""
        deadline = time.time() + timeout
        last_data = time.time()
        while time.time() < deadline:
            try:
                chunk = self._queue.get(timeout=0.2)
            except queue.Empty:
                tail = buffer[-200:]
                if PROMPT.search(tail.split("\n")[-1]) and time.time() - last_data > QUIET_PERIOD:
                    return buffer
                continue
            if chunk is None:
                return buffer
            text = chunk.decode("utf-8", "replace")
            buffer += text
            self.transcript.append(text)
            last_data = time.time()
            if PAGER.search(buffer[-120:]):
                buffer = PAGER.sub("", buffer)
                self._write(" ")
        return buffer

    def run(self, command, timeout=COMMAND_TIMEOUT):
        """Send one command and return everything the switch printed for it."""
        if self.verbose:
            print(f"  {self.address} > {command}")
        self._write(command + "\r\n")
        output = self._drain(timeout)
        if PASSWORD.search(output[-80:]):
            raise SwitchError(
                f"{self.address} asked for a password running {command!r}; this tool drives "
                f"the switch by key only"
            )
        if "Error:" in output or "Bad command" in output:
            detail = next((l.strip() for l in output.split("\n") if "Error" in l or "Bad command" in l), "")
            raise SwitchError(f"{self.address} rejected {command!r}: {detail}")
        return output

    def _logout(self):
        """End the session for real. See the session-table note at the top."""
        for command in ("end", "logout"):
            try:
                self._write(command + "\r\n")
                self._drain(5)
            except Exception:
                return

    def full_transcript(self):
        return "".join(self.transcript)
