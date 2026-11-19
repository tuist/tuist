#!/usr/bin/env bash
# Exercises a locally loaded sandbox guest image: recording and image tools,
# and the agent's Tuist access configuration.
set -euo pipefail

image=${1:?usage: sandbox-image-check-guest.sh <image>}

docker run --rm --read-only --user user --tmpfs /tmp:rw,size=64m \
  --entrypoint sh -i "$image" -eu <<'EOF'
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
ffmpeg -v error -f lavfi -i color=c=blue:s=16x16:d=0.2 \
  -c:v libx264 -pix_fmt yuv420p "$work/recording.mp4"
ffmpeg -v error -i "$work/recording.mp4" -frames:v 1 "$work/frame.png"
convert "$work/frame.png" -resize 8x8 "$work/thumbnail.png"
test "$(identify -format '%wx%h' "$work/thumbnail.png")" = 8x8
EOF

# Not --read-only: the CLI writes under the passwd home of `user`,
# whatever HOME says, and that home is writable in the guest.
docker run --rm --user user --entrypoint sh -i "$image" -eu <<'EOF'
tuist version
test -O /home/user/.claude/skills/verifying-work-with-tuist/SKILL.md
EOF
