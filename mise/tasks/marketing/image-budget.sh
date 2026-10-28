#!/usr/bin/env bash
#MISE description="Check all served raster images and the shared marketing header budget"
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../../.."

readonly ROOT="server/priv/static"

# Static images are Largest Contentful Paint candidates: the marketing hero and
# every blog post header and the signup artwork render above the fold. Animated GIFs are
# lazy and below the fold, so they get a looser budget, but they still land on
# the reader's connection in full.
readonly STATIC_MAX_KB=500
readonly ANIMATED_MAX_KB=3200
# The soft header artwork paints above the fold. A 66 KB variant delayed LCP
# by about a second in the throttled benchmark; the compact variants use 8–11 KiB.
readonly HEADER_MAX_KB=20
readonly HEADER_MAX_DIMENSION=1024

if command -v magick >/dev/null 2>&1; then
  identify=(magick identify)
elif command -v identify >/dev/null 2>&1; then
  identify=(identify)
else
  echo "ImageMagick is required: brew install imagemagick or apt-get install imagemagick" >&2
  exit 1
fi

offenders=0
total_bytes=0

while IFS= read -r -d '' file; do
  size_bytes=$(( $(wc -c <"$file") ))
  total_bytes=$((total_bytes + size_bytes))
  invalid=0

  case "$file" in
    */hero-background*) budget=$HEADER_MAX_KB ;;
    *.[gG][iI][fF]) budget=$ANIMATED_MAX_KB ;;
    *) budget=$STATIC_MAX_KB ;;
  esac

  if [ "$size_bytes" -gt "$((budget * 1024))" ]; then
    printf '%s is %s bytes, over the %s KiB budget\n' "${file#"$ROOT"/}" "$size_bytes" "$budget" >&2
    invalid=1
  fi

  case "$file" in
    */hero-background*)
      if dimensions=$("${identify[@]}" -ping -format '%w %h' "${file}[0]"); then
        read -r width height <<< "$dimensions"
        if [ "$width" -gt "$HEADER_MAX_DIMENSION" ] || [ "$height" -gt "$HEADER_MAX_DIMENSION" ]; then
          printf '%s is %sx%s, over the header limit of %s pixels per dimension\n' \
            "${file#"$ROOT"/}" "$width" "$height" "$HEADER_MAX_DIMENSION" >&2
          invalid=1
        fi
      else
        printf 'Cannot read header image dimensions: %s\n' "${file#"$ROOT"/}" >&2
        invalid=1
      fi
      ;;
  esac

  if [ "$invalid" -eq 1 ]; then
    offenders=$((offenders + 1))
  fi
done < <(find "$ROOT" -type f \( \
  -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o \
  -iname '*.webp' -o -iname '*.gif' -o -iname '*.avif' \
\) -print0)

if [ "$offenders" -gt 0 ]; then
  cat >&2 <<EOF

$offenders image(s) over budget. Resize to the dimensions the page actually
renders rather than committing the export straight out of the capture tool:

  magick in.png -resize 1600x -quality 82 -strip out.png
  ffmpeg -i in.gif -vf "fps=12,scale=800:-1:flags=lanczos,split[s0][s1]\
;[s0]palettegen=max_colors=64:stats_mode=diff[p];[s1][p]paletteuse" -loop 0 out.gif

Open Graph cards only need 1200x630. Nothing on the site renders wider than
about 1600 CSS pixels at 2x.

Shared hero-background* images must fit ${HEADER_MAX_KB} KiB and
${HEADER_MAX_DIMENSION} pixels per dimension. Keep regeneration sources outside
priv/static; everything there is served and checked.
EOF
  exit 1
fi

total_mb=$(awk -v bytes="$total_bytes" 'BEGIN { printf "%.1f", bytes / 1048576 }')
echo "All served raster images are within budget (${total_mb} MiB total)"
