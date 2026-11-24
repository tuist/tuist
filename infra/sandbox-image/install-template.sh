#!/bin/sh
# Installs the template carried in this image onto the node. Runs as the init
# container of the template installer DaemonSet (and of remote execution's
# daemons) with the node's /data/sandboxes mounted at /host. Idempotent: a
# directory that already holds rootfs.ext4 is left alone and only
# metadata.json is rewritten. Once the tag is complete it becomes the one the
# template's `current` file names, which a sandboxd without TEMPLATE_TAG
# follows. sandboxd adds the `ready` marker itself once it has taken the
# template snapshot.
set -eu

: "${TEMPLATE_TAG:?TEMPLATE_TAG must be set}"
TEMPLATE_NAME="${TEMPLATE_NAME:-default}"
TEMPLATE_DIR="${TEMPLATE_DIR:-/host/templates/${TEMPLATE_NAME}/${TEMPLATE_TAG}}"
# The rootfs every sandbox of this template gets. The image carries it at its
# used size; it is grown here, sparse, so the node's image store and data
# disk only ever hold what is written. sandboxd reports this file's size and
# the server reserves it for every sandbox on the node.
ROOTFS_SIZE="${ROOTFS_SIZE:-12G}"

# The copy is assembled outside the templates directory and renamed into
# place whole, so a running sandboxd never lists, uses or prunes a tag that is
# still being copied. It must be on the same filesystem as TEMPLATE_DIR.
STAGING_DIR="${TEMPLATE_STAGING_DIR:-/host/template-staging}/${TEMPLATE_NAME}-${TEMPLATE_TAG}"

if [ -f "$TEMPLATE_DIR/rootfs.ext4" ]; then
    echo "template already present in $TEMPLATE_DIR, keeping it"
else
    rm -rf "$STAGING_DIR"
    mkdir -p "$STAGING_DIR" "$(dirname "$TEMPLATE_DIR")"
    for file in vmlinux vmlinux.config rootfs.ext4; do
        echo "copying $file to $STAGING_DIR"
        cp --sparse=always "/template/$file" "$STAGING_DIR/$file"
        if [ "$file" = rootfs.ext4 ]; then
            echo "growing rootfs.ext4 to at least $ROOTFS_SIZE"
            truncate -s ">$ROOTFS_SIZE" "$STAGING_DIR/$file"
            # e2fsck exits 1 after correcting something; resize2fs requires a
            # fresh check. Zeroing the new inode tables here, as punched holes,
            # marks them initialised, so guests never write those zeros into
            # their own rootfs clones at mount.
            e2fsck -fy "$STAGING_DIR/$file" || [ "$?" -le 1 ]
            RESIZE2FS_FORCE_ITABLE_INIT=1 resize2fs "$STAGING_DIR/$file"
        fi
    done
    sync
    # An interrupted earlier install may have left a directory without a
    # rootfs here.
    rm -rf "$TEMPLATE_DIR"
    mv "$STAGING_DIR" "$TEMPLATE_DIR"
fi

# metadata.json is a single line ending in "}", so the tag is spliced in.
rootfs_bytes="$(stat -c %s "$TEMPLATE_DIR/rootfs.ext4")"
sed "s|}\$|,\"tag\":\"${TEMPLATE_TAG}\",\"rootfs_bytes\":${rootfs_bytes}}|" /template/metadata.json > "$TEMPLATE_DIR/metadata.json.tmp"
mv "$TEMPLATE_DIR/metadata.json.tmp" "$TEMPLATE_DIR/metadata.json"
sync

# Point the template at this tag last, once every file is in place.
current="$(dirname "$TEMPLATE_DIR")/current"
printf '%s\n' "$TEMPLATE_TAG" > "$current.tmp"
mv "$current.tmp" "$current"
sync

echo "installed template ${TEMPLATE_NAME}:${TEMPLATE_TAG} in $TEMPLATE_DIR"
cat "$TEMPLATE_DIR/metadata.json"
du -h "$TEMPLATE_DIR"/* || true
