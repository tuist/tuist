#!/bin/sh
# Installs the template carried in this image onto the node. Runs as an init
# container of the sandboxd DaemonSet with the node's /data/sandboxes mounted
# at /host. Idempotent: a directory that already holds rootfs.ext4 is left
# alone and only metadata.json is rewritten. sandboxd adds the `ready` marker
# itself once it has taken the template snapshot.
set -eu

: "${TEMPLATE_TAG:?TEMPLATE_TAG must be set}"
TEMPLATE_NAME="${TEMPLATE_NAME:-default}"
TEMPLATE_DIR="${TEMPLATE_DIR:-/host/templates/${TEMPLATE_NAME}/${TEMPLATE_TAG}}"
# The rootfs every sandbox of this template gets. The image carries it at its
# used size; it is grown here, sparse, so the node's image store and data
# disk only ever hold what is written. sandboxd reports this file's size and
# the server reserves it for every sandbox on the node.
ROOTFS_SIZE="${ROOTFS_SIZE:-12G}"

mkdir -p "$TEMPLATE_DIR"
if [ -f "$TEMPLATE_DIR/rootfs.ext4" ]; then
    echo "template already present in $TEMPLATE_DIR, keeping it"
else
    # rootfs.ext4 goes last because its presence is what marks the copy as
    # complete, and every file lands under a temporary name first so a killed
    # container never leaves a truncated file under the final one.
    for file in vmlinux vmlinux.config rootfs.ext4; do
        echo "copying $file to $TEMPLATE_DIR"
        cp --sparse=always "/template/$file" "$TEMPLATE_DIR/$file.tmp"
        if [ "$file" = rootfs.ext4 ]; then
            echo "growing rootfs.ext4 to at least $ROOTFS_SIZE"
            truncate -s ">$ROOTFS_SIZE" "$TEMPLATE_DIR/$file.tmp"
            # e2fsck exits 1 after correcting something; resize2fs requires a
            # fresh check. Zeroing the new inode tables here, as punched holes,
            # marks them initialised, so guests never write those zeros into
            # their own rootfs clones at mount.
            e2fsck -fy "$TEMPLATE_DIR/$file.tmp" || [ "$?" -le 1 ]
            RESIZE2FS_FORCE_ITABLE_INIT=1 resize2fs "$TEMPLATE_DIR/$file.tmp"
        fi
        mv "$TEMPLATE_DIR/$file.tmp" "$TEMPLATE_DIR/$file"
    done
fi

# metadata.json is a single line ending in "}", so the tag is spliced in.
rootfs_bytes="$(stat -c %s "$TEMPLATE_DIR/rootfs.ext4")"
sed "s|}\$|,\"tag\":\"${TEMPLATE_TAG}\",\"rootfs_bytes\":${rootfs_bytes}}|" /template/metadata.json > "$TEMPLATE_DIR/metadata.json.tmp"
mv "$TEMPLATE_DIR/metadata.json.tmp" "$TEMPLATE_DIR/metadata.json"
sync

echo "installed template ${TEMPLATE_NAME}:${TEMPLATE_TAG} in $TEMPLATE_DIR"
cat "$TEMPLATE_DIR/metadata.json"
du -h "$TEMPLATE_DIR"/* || true
