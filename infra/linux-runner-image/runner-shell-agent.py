#!/usr/bin/env python3
import base64
import fcntl
import json
import os
import pty
import pwd
import select
import socket
import ssl
import struct
import sys
import termios
import time
import urllib.error
import urllib.parse
import urllib.request


TOKEN_PATHS = (
    "/etc/tuist-sa-token",
    "/var/run/secrets/tuist-runner/token",
)


def log(message):
    print(f"{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} runner-shell-agent: {message}", flush=True)


def token_path():
    configured = os.environ.get("TUIST_RUNNER_TOKEN_PATH")
    if configured:
        return configured

    for path in TOKEN_PATHS:
        if os.path.exists(path):
            return path

    return TOKEN_PATHS[-1]


def read_token():
    with open(token_path(), "r", encoding="utf-8") as file:
        return file.read().strip()


def discovery_url():
    configured = os.environ.get("TUIST_RUNNER_SHELL_DISCOVERY_URL")
    if configured:
        return configured

    base_url = os.environ["TUIST_RUNNER_DISPATCH_URL"].rstrip("/")
    if base_url.endswith("/dispatch"):
        base_url = base_url[: -len("/dispatch")]
    return base_url + "/interactive/shell/sessions"


def websocket_url(session, discovery):
    raw_url = session["websocket_url"]
    if os.environ.get("TUIST_RUNNER_SHELL_USE_DISCOVERY_ORIGIN", "1") == "0":
        return raw_url

    discovered = urllib.parse.urlparse(discovery)
    websocket = urllib.parse.urlparse(raw_url)
    scheme = "wss" if discovered.scheme == "https" else "ws"
    return urllib.parse.urlunparse((scheme, discovered.netloc, websocket.path, websocket.params, websocket.query, websocket.fragment))


def wait_for_claim():
    jit_path = os.environ.get("TUIST_RUNNER_JIT_PATH")
    if not jit_path:
        return

    log(f"waiting for a claimed job (JIT at {jit_path}) before accepting shell sessions")
    while not os.path.exists(jit_path):
        time.sleep(1)


def discover_session(url, token):
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})

    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            if response.status == 204:
                return None
            if response.status != 200:
                log(f"session discovery returned HTTP {response.status}")
                return None
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        if error.code not in (204, 404):
            log(f"session discovery returned HTTP {error.code}")
    except Exception as error:
        log(f"session discovery failed: {error}")

    return None


def recv_exact(sock, length):
    chunks = []
    remaining = length
    while remaining > 0:
        chunk = sock.recv(remaining)
        if not chunk:
            raise ConnectionError("socket closed")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def send_ws_frame(sock, opcode, payload=b""):
    if isinstance(payload, str):
        payload = payload.encode("utf-8")

    header = bytearray([0x80 | opcode])
    length = len(payload)
    if length < 126:
        header.append(0x80 | length)
    elif length < 65536:
        header.extend((0x80 | 126, (length >> 8) & 0xFF, length & 0xFF))
    else:
        header.append(0x80 | 127)
        header.extend(length.to_bytes(8, "big"))

    mask = os.urandom(4)
    masked = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
    sock.sendall(bytes(header) + mask + masked)


def recv_ws_frame(sock):
    first, second = recv_exact(sock, 2)
    opcode = first & 0x0F
    masked = second & 0x80
    length = second & 0x7F

    if length == 126:
        length = int.from_bytes(recv_exact(sock, 2), "big")
    elif length == 127:
        length = int.from_bytes(recv_exact(sock, 8), "big")

    mask = recv_exact(sock, 4) if masked else b""
    payload = recv_exact(sock, length) if length else b""
    if masked:
        payload = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))

    return opcode, payload


def connect_websocket(url, token):
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in ("ws", "wss"):
        raise ValueError(f"unsupported websocket scheme: {parsed.scheme}")

    port = parsed.port or (443 if parsed.scheme == "wss" else 80)
    host = parsed.hostname
    raw = socket.create_connection((host, port), timeout=10)
    if parsed.scheme == "wss":
        raw = ssl.create_default_context().wrap_socket(raw, server_hostname=host)

    path = parsed.path or "/"
    if parsed.query:
        path += "?" + parsed.query

    host_header = parsed.netloc
    key = base64.b64encode(os.urandom(16)).decode("ascii")
    request = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: {host_header}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        f"Authorization: Bearer {token}\r\n"
        "\r\n"
    )
    raw.sendall(request.encode("ascii"))

    response = b""
    while b"\r\n\r\n" not in response:
        response += raw.recv(4096)
        if not response:
            raise ConnectionError("websocket handshake closed")

    status = response.split(b"\r\n", 1)[0]
    if b" 101 " not in status:
        raise ConnectionError(status.decode("ascii", errors="replace"))

    raw.settimeout(None)
    return raw


def drop_to_shell_user():
    if os.getuid() != 0:
        return

    user = os.environ.get("TUIST_RUNNER_SHELL_USER", "runner")
    try:
        info = pwd.getpwnam(user)
    except KeyError:
        log(f"shell user {user!r} missing; keeping current uid")
        return

    os.initgroups(info.pw_name, info.pw_gid)
    os.setgid(info.pw_gid)
    os.setuid(info.pw_uid)
    os.environ["HOME"] = info.pw_dir
    os.environ["USER"] = info.pw_name
    os.environ["LOGNAME"] = info.pw_name


def shell_workdir():
    candidates = [
        os.environ.get("TUIST_RUNNER_SHELL_WORKDIR"),
        "/home/runner/actions-runner/_work",
        "/Users/runner/work",
        os.path.expanduser("~"),
    ]

    for path in candidates:
        if path and os.path.isdir(path):
            return path

    return "/"


def spawn_shell():
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(shell_workdir())
        os.environ.setdefault("TERM", "xterm-256color")
        os.environ["TUIST_RUNNER_INTERACTIVE_SHELL"] = "1"
        shell = os.environ.get("TUIST_RUNNER_SHELL_PATH", os.environ.get("SHELL", "/bin/bash"))
        drop_to_shell_user()
        os.execlp(shell, shell, "-l")

    return pid, fd


def resize_pty(fd, columns, rows):
    if columns <= 0 or rows <= 0:
        return

    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))


def reap_shell(pid):
    try:
        _, status = os.waitpid(pid, os.WNOHANG)
        if status == 0:
            return None
        if os.WIFEXITED(status):
            return os.WEXITSTATUS(status)
        if os.WIFSIGNALED(status):
            return 128 + os.WTERMSIG(status)
    except ChildProcessError:
        return 0

    return None


def handle_text_frame(payload, pty_fd):
    try:
        message = json.loads(payload.decode("utf-8"))
    except Exception:
        return

    if message.get("type") == "resize":
        resize_pty(pty_fd, int(message.get("columns", 0)), int(message.get("rows", 0)))


def bridge_session(session, token, discovery):
    url = websocket_url(session, discovery)
    log(f"connecting shell tunnel for session {session.get('session_id')} -> {url}")
    sock = connect_websocket(url, token)
    pid, pty_fd = spawn_shell()

    try:
        while True:
            readable, _, _ = select.select([sock, pty_fd], [], [], 1)

            if sock in readable:
                opcode, payload = recv_ws_frame(sock)
                if opcode == 0x1:
                    handle_text_frame(payload, pty_fd)
                elif opcode == 0x2:
                    os.write(pty_fd, payload)
                elif opcode == 0x8:
                    break
                elif opcode == 0x9:
                    send_ws_frame(sock, 0xA, payload)

            if pty_fd in readable:
                try:
                    data = os.read(pty_fd, 8192)
                except OSError:
                    data = b""
                if not data:
                    break
                send_ws_frame(sock, 0x2, data)

            exit_status = reap_shell(pid)
            if exit_status is not None:
                send_ws_frame(sock, 0x1, json.dumps({"type": "exit", "status": exit_status}))
                break
    finally:
        try:
            os.close(pty_fd)
        except OSError:
            pass
        try:
            os.kill(pid, 15)
        except OSError:
            pass
        try:
            send_ws_frame(sock, 0x8, b"")
        except Exception:
            pass
        sock.close()


def main():
    if not os.environ.get("TUIST_RUNNER_DISPATCH_URL"):
        log("TUIST_RUNNER_DISPATCH_URL unset; shell agent disabled")
        return 0

    wait_for_claim()
    url = discovery_url()
    log(f"polling shell sessions at {url}")

    while True:
        try:
            token = read_token()
            session = discover_session(url, token)
            if session:
                bridge_session(session, token, url)
        except Exception as error:
            log(f"shell bridge failed: {error}")

        time.sleep(2)


if __name__ == "__main__":
    sys.exit(main())
