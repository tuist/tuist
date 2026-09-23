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
        mv "$TEMPLATE_DIR/$file.tmp" "$TEMPLATE_DIR/$file"
    done
fi

# metadata.json is a single line ending in "}", so the tag is spliced in.
sed "s|}\$|,\"tag\":\"${TEMPLATE_TAG}\"}|" /template/metadata.json > "$TEMPLATE_DIR/metadata.json.tmp"
mv "$TEMPLATE_DIR/metadata.json.tmp" "$TEMPLATE_DIR/metadata.json"
sync

echo "installed template ${TEMPLATE_NAME}:${TEMPLATE_TAG} in $TEMPLATE_DIR"
cat "$TEMPLATE_DIR/metadata.json"
du -h "$TEMPLATE_DIR"/* || true
