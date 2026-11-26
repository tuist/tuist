#!/bin/sh
# Adds the sandbox guest contract to the image being built (the Dockerfile's
# `agents` stage), whatever image it started from: the default `guest` stage,
# the Linux runner image or a customer's image. It only uses tools the
# contract itself requires, never a package manager, so it behaves the same on
# every base; a base that lacks something fails here with its name.
set -eu

fail() {
    echo "sandbox guest contract: $*" >&2
    exit 1
}

# What sandboxd and the server run in every guest: /bin/sh and /bin/bash
# scripts, /bin/umount (prepared checkouts), /bin/sync (pauses), mkfs.ext4
# (workspace format), resize2fs (rootfs growth), git and tar (sbx-worker
# checkouts), and sudo and runuser for the agent user.
for path in /bin/sh /bin/bash /bin/umount /bin/sync; do
    [ -x "$path" ] || fail "missing $path"
done
for tool in mkfs.ext4 resize2fs git tar sudo runuser useradd groupadd visudo; do
    command -v "$tool" >/dev/null 2>&1 || fail "missing $tool"
done

# The agent user is UID/GID 1000 in every template, the Linux runner image's
# `runner` too, so caches and checkouts CI wrote keep their owner. Amp's
# contract and sbx-worker name it `user`: an image whose UID 1000 has another
# name (the runner image's `runner`) gets `user` as a second name for the same
# account, with its home at /home/user.
getent passwd 1000 >/dev/null || fail "no account with UID 1000"
getent group 1000 >/dev/null || fail "no group with GID 1000"
if ! getent passwd user >/dev/null; then
    useradd --non-unique --uid 1000 --gid 1000 --home-dir /home/user --create-home --shell /bin/bash user
fi
[ "$(id -u user)" = 1000 ] || fail "user is UID $(id -u user), not 1000"
[ "$(id -g user)" = 1000 ] || fail "user is GID $(id -g user), not 1000"
[ -d /home/user ] || fail "user has no /home/user"
# Amp bootstraps as `user` with passwordless sudo.
if ! sudo -n -l -U user 2>/dev/null | grep -q 'NOPASSWD: ALL'; then
    echo 'user ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/amp-user
    chmod 0440 /etc/sudoers.d/amp-user
    visudo -cf /etc/sudoers.d/amp-user >/dev/null
fi

# REAPI actions run as `builder` (UID/GID 2000, internal/executor.actionUID):
# it cannot read the root worker's CAS credential or control sockets and,
# unlike `user`, has no sudo.
if ! getent passwd builder >/dev/null; then
    getent group 2000 >/dev/null && fail "GID 2000 is taken, builder needs it"
    getent passwd 2000 >/dev/null && fail "UID 2000 is taken, builder needs it"
    groupadd --gid 2000 builder
    useradd --uid 2000 --gid builder --create-home builder
fi
[ "$(id -u builder)" = 2000 ] || fail "builder is UID $(id -u builder), not 2000"

mkdir -p /workspace /mnt/memory /run /tmp /proc /sys /dev
chmod 1777 /tmp

# The image's ENV (ANDROID_HOME, ImageOS, ...) is image configuration, not a
# file, so the ext4 rootfs would lose it. Keep it for login shells. Build-time
# and per-process variables are left out.
export -p \
    | grep -Ev '^export (HOME|HOSTNAME|PWD|OLDPWD|SHLVL|TERM|DEBIAN_FRONTEND|EMBEDDED_EXECUTOR)=' \
    | grep -E '^export [A-Za-z_][A-Za-z0-9_]*=' > /etc/profile.d/00-image-env.sh || true
chmod 0644 /etc/profile.d/00-image-env.sh
