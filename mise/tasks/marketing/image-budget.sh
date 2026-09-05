#!/usr/bin/env bash
#MISE description="Fail when a marketing image exceeds its size budget"
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../../.."

readonly ROOT="server/priv/static/marketing/images"

# Static images are Largest Contentful Paint candidates: the marketing hero and
# every blog post header render eagerly and above the fold. Animated GIFs are
# lazy and below the fold, so they get a looser budget, but they still land on
# the reader's connection in full.
readonly STATIC_MAX_KB=500
readonly ANIMATED_MAX_KB=3200

offenders=0

while IFS= read -r file; do
  size_kb=$(( $(wc -c <"$file") / 1024 ))

  case "$file" in
    *.gif) budget=$ANIMATED_MAX_KB ;;
    *) budget=$STATIC_MAX_KB ;;
  esac

  if [ "$size_kb" -gt "$budget" ]; then
    printf '%s is %s KB, over the %s KB budget\n' "${file#"$ROOT"/}" "$size_kb" "$budget" >&2
    offenders=$((offenders + 1))
  fi
done < <(find "$ROOT" -type f \( \
  -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o \
  -name '*.webp' -o -name '*.gif' -o -name '*.avif' \
\) | sort)

if [ "$offenders" -gt 0 ]; then
  cat >&2 <<EOF

$offenders image(s) over budget. Resize to the dimensions the page actually
renders rather than committing the export straight out of the capture tool:

  magick in.png -resize 1600x -quality 82 -strip out.png
  ffmpeg -i in.gif -vf "fps=12,scale=800:-1:flags=lanczos,split[s0][s1]\
;[s0]palettegen=max_colors=64:stats_mode=diff[p];[s1][p]paletteuse" -loop 0 out.gif

Open Graph cards only need 1200x630. Nothing on the site renders wider than
about 1600 CSS pixels at 2x.
EOF
  exit 1
fi

total_mb=$(find "$ROOT" -type f -exec wc -c {} \; | awk '{ total += $1 } END { printf "%.1f", total / 1048576 }')
echo "All marketing images are within budget (${total_mb} MB total)"
