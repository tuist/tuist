"""Tuist's file credentials and POSIX refresh-lock contract, shared with the CLI."""

import argparse
import base64
import fcntl
import getpass
import json
import os
import secrets
import stat
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from contextlib import contextmanager
from pathlib import Path


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class AuthenticationError(ValueError):
    pass


class HTTPError(AuthenticationError):
    def __init__(self, status, error=None):
        super().__init__(f"Authentication request failed (HTTP {status})")
        self.status = status
        self.error = error


def origin(url):
    parts = urllib.parse.urlsplit(url)
    if (
        any(c.isspace() for c in url)
        or not parts.hostname
        or parts.username
        or parts.password
        or parts.query
        or parts.fragment
        or parts.path not in ("", "/")
        or not (
            parts.scheme == "https"
            or parts.scheme == "http"
            and parts.hostname in ("localhost", "127.0.0.1", "::1")
        )
    ):
        raise AuthenticationError(
            "Use an HTTPS Tuist origin (HTTP is allowed only for loopback development)"
        )
    return url.rstrip("/")


def request(url, body=None, headers=None, retry=False, form=False):
    headers = {"Accept": "application/json", **(headers or {})}
    if body is not None:
        headers["Content-Type"] = (
            "application/x-www-form-urlencoded" if form else "application/json"
        )
        body = (urllib.parse.urlencode(body) if form else json.dumps(body)).encode()
    opener = urllib.request.build_opener(NoRedirect())
    for attempt in range(4):
        try:
            with opener.open(
                urllib.request.Request(url, data=body, headers=headers), timeout=30
            ) as response:
                return response.status, json.load(response)
        except urllib.error.HTTPError as error:
            if (
                retry
                and attempt < 3
                and (error.code in (408, 429) or error.code >= 500)
            ):
                error.close()
            else:
                try:
                    code = json.load(error).get("error")
                except (ValueError, AttributeError):
                    code = None
                finally:
                    error.close()
                raise HTTPError(error.code, code) from None
        except (OSError, urllib.error.URLError):
            if not retry or attempt == 3:
                raise AuthenticationError(
                    "Authentication service unavailable; credentials were preserved"
                ) from None
        time.sleep((0.25, 1, 2)[attempt])


def home(kind, fallback):
    value = os.environ.get("TUIST_XDG_" + kind) or os.environ.get("XDG_" + kind)
    return (
        Path(os.path.normpath(value))
        if value and Path(value).is_absolute()
        else Path.home() / fallback
    )


def credential_path(url, aliases=True):
    directory = home("CONFIG_HOME", ".config") / "tuist/credentials"
    host = urllib.parse.urlsplit(url).hostname.lower().rstrip(".")
    canonical = directory / (host + ".json")
    # A missing ancestor is absence; dangling links and inaccessible/non-directory
    # ancestors must never silently turn existing credentials into a fresh login.
    for ancestor in reversed((directory, *directory.parents)):
        try:
            info = ancestor.stat()
        except FileNotFoundError:
            if ancestor.is_symlink():
                raise AuthenticationError(
                    "Could not inspect the Tuist credentials directory"
                ) from None
            continue
        if not stat.S_ISDIR(info.st_mode):
            raise AuthenticationError(
                "Could not inspect the Tuist credentials directory"
            )
    if not aliases or os.path.lexists(canonical):
        return canonical
    try:
        for path in sorted(directory.iterdir()):
            if path.name.endswith(".json") and path.stem.lower().rstrip(".") == host:
                return path
    except FileNotFoundError:
        pass
    return canonical


def read(url):
    path = credential_path(url)
    try:
        value = json.loads(path.read_text())
    except FileNotFoundError:
        if os.path.lexists(path):
            raise AuthenticationError(
                "Existing Tuist credentials are unreadable"
            ) from None
        return None
    except (ValueError, OSError):
        raise AuthenticationError(
            "Existing Tuist credentials are invalid; sign in again"
        ) from None
    if (
        not isinstance(value, dict)
        or not isinstance(value.get("accessToken"), str)
        or not value["accessToken"].strip()
    ):
        raise AuthenticationError(
            "Existing Tuist credentials are invalid; sign in again"
        )
    return value


def lock_path(url):
    # FNV-1a UInt64 over the canonical absolute pathname, exactly as Swift/Kotlin.
    value = 14695981039346656037
    for byte in str(credential_path(url, aliases=False)).encode():
        value = ((value ^ byte) * 1099511628211) & 0xFFFFFFFFFFFFFFFF
    return (
        home("STATE_HOME", ".local/state")
        / f"tuist/cached_value_store/credential-refresh-{value:x}.lock"
    )


@contextmanager
def locked(url, timeout=30):
    path = lock_path(url)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path, os.O_CREAT | os.O_WRONLY, 0o600)
    try:
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise AuthenticationError(
                        "Timed out waiting for the credential refresh lock; credentials were preserved"
                    ) from None
                time.sleep(0.1)
        yield
    finally:
        os.close(fd)
        # Never unlink: waiters and later arrivals must lock the same inode.


def save(url, credentials):
    path = credential_path(url)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".credentials-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(credentials, stream)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def claims(token):
    if not isinstance(token, str):
        raise AuthenticationError("Stored Tuist token is invalid; sign in again")
    try:
        payload = token.split(".")[1]
        value = json.loads(
            base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4))
        )
        if isinstance(value, dict):
            return value
    except (ValueError, IndexError):
        pass
    raise AuthenticationError("Stored Tuist token is invalid; sign in again")


def valid(token):
    expiration = claims(token).get("exp")
    return (
        isinstance(expiration, (int, float))
        and not isinstance(expiration, bool)
        and expiration > time.time() + 30
    )


def token(url):
    url = origin(url)
    supplied = os.environ.get("TUIST_TOKEN")
    if supplied is not None:
        if not supplied or any(c.isspace() for c in supplied):
            raise AuthenticationError(
                "TUIST_TOKEN must not be blank or contain whitespace"
            )
        return supplied
    with locked(url):
        credentials = read(url)
        if not credentials or credentials.get("rejected"):
            raise AuthenticationError(
                "Sign in with bazel run @rules_tuist//:login, or set TUIST_TOKEN"
            )
        access = credentials["accessToken"]
        if valid(access):
            return access
        refresh = credentials.get("refreshToken")
        if not isinstance(refresh, str) or not refresh:
            raise AuthenticationError(
                "Session expired; sign in with bazel run @rules_tuist//:login"
            )
        oauth = claims(refresh).get("type") == "account"
        body = {"refresh_token": refresh}
        if oauth:
            body.update(
                grant_type="refresh_token",
                client_id=credentials.get("oauthClientID")
                or os.environ.get("TUIST_OAUTH_CLIENT_ID")
                or "b3298a92-3deb-4f5e-a526-b7ad324979b5",
            )
        try:
            _, result = request(
                url + ("/oauth2/token" if oauth else "/api/auth/refresh_token"),
                body,
                retry=True,
                form=oauth,
            )
            if (
                not isinstance(result, dict)
                or not valid(result.get("access_token", ""))
                or not isinstance(result.get("refresh_token"), str)
                or not result["refresh_token"]
            ):
                raise AuthenticationError(
                    "Authentication returned an invalid token pair; credentials were preserved"
                )
        except HTTPError as error:
            current = read(url)
            if current != credentials:
                raise AuthenticationError(
                    "The session changed during refresh; retry the command"
                ) from None
            if (
                error.status in (401, 403)
                or error.status == 400
                and (not oauth or error.error == "invalid_grant")
            ):
                save(url, {**credentials, "rejected": True})
            raise
        # Older clients and interactive login may write without this lock. Never
        # overwrite their rotated session, or resurrect one they signed out of.
        if read(url) != credentials:
            raise AuthenticationError(
                "The session changed during refresh; retry the command"
            )
        save(
            url,
            {
                **credentials,
                "accessToken": result["access_token"],
                "refreshToken": result["refresh_token"],
            },
        )
        return result["access_token"]


def login(url, email=None, password=None):
    url = origin(url)
    if email is not None or password is not None:
        _, result = request(
            url + "/api/auth",
            {
                "email": email or input("Email: "),
                "password": password or getpass.getpass(),
            },
        )
    elif "TUIST_OIDC_TOKEN" in os.environ or any(
        os.environ.get(name)
        for name in ("CI", "GITHUB_ACTIONS", "CIRCLECI", "BITRISE_IO")
    ):
        if (
            "TUIST_OIDC_TOKEN" in os.environ
            and not os.environ["TUIST_OIDC_TOKEN"].strip()
        ):
            raise AuthenticationError("TUIST_OIDC_TOKEN must not be blank")
        identity = (
            os.environ.get("TUIST_OIDC_TOKEN")
            or os.environ.get("CIRCLE_OIDC_TOKEN_V2")
            or os.environ.get("CIRCLE_OIDC_TOKEN")
            or os.environ.get("BITRISE_OIDC_ID_TOKEN")
            or os.environ.get("BITRISE_IDENTITY_TOKEN")
        )
        if not identity and os.environ.get("GITHUB_ACTIONS"):
            endpoint = os.environ.get("ACTIONS_ID_TOKEN_REQUEST_URL", "")
            bearer = os.environ.get("ACTIONS_ID_TOKEN_REQUEST_TOKEN", "")
            if not endpoint.startswith("https://") or not bearer:
                raise AuthenticationError(
                    "GitHub Actions authentication requires id-token: write"
                )
            _, response = request(
                endpoint + ("&" if "?" in endpoint else "?") + "audience=tuist",
                headers={"Authorization": "Bearer " + bearer},
                retry=True,
            )
            identity = response.get("value")
        if not identity or not identity.strip():
            raise AuthenticationError(
                "Supply TUIST_OIDC_TOKEN with audience tuist for CI authentication"
            )
        body = {"token": identity.strip()}
        if os.environ.get("TUIST_OIDC_ACCOUNT", "").strip():
            body["account_handle"] = os.environ["TUIST_OIDC_ACCOUNT"].strip()
        _, result = request(url + "/api/auth/oidc/token", body)
    else:
        code = secrets.token_urlsafe(24)
        browser = url + f"/auth/device_codes/{code}?type=cli"
        print("Sign in in your browser: " + browser, flush=True)
        webbrowser.open(browser)
        for _ in range(300):
            status, result = request(url + "/api/auth/device_code/" + code, retry=True)
            if status == 200:
                break
            if status != 202:
                raise AuthenticationError("Unexpected device authentication response")
            time.sleep(1)
        else:
            raise AuthenticationError("Browser authentication timed out")
    if not isinstance(result, dict) or not valid(result.get("access_token", "")):
        raise AuthenticationError("Authentication returned an invalid token")
    credentials = {"accessToken": result["access_token"]}
    if "refresh_token" in result:
        credentials["refreshToken"] = result["refresh_token"]
    with locked(url):
        # Explicit login replaces corrupt/rejected credentials, unlike refresh.
        save(url, credentials)


def main():
    parser = argparse.ArgumentParser(description="Sign in to Tuist from Bazel")
    parser.add_argument(
        "--url", default=os.environ.get("TUIST_URL", "https://tuist.dev")
    )
    parser.add_argument("--email")
    parser.add_argument("--password")
    args = parser.parse_args()
    login(args.url, args.email, args.password)
    print("Successfully logged in.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyboardInterrupt):
        print(
            "Tuist authentication failed; no credentials were printed. Retry sign-in or check connectivity.",
            file=sys.stderr,
        )
        sys.exit(1)
