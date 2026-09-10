#!/usr/bin/env bash
#MISE description="Exercise image budget coverage and regression cases"
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../../.."

fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/mise/tasks/marketing" "$fixture/server/priv/static"
cp mise/tasks/marketing/image-budget.sh "$fixture/mise/tasks/marketing/"
root="$fixture/server/priv/static"

if command -v magick >/dev/null 2>&1; then
  convert=(magick)
else
  convert=(convert)
fi

expect_pass() {
  if ! output=$(bash "$fixture/mise/tasks/marketing/image-budget.sh" 2>&1); then
    printf 'FAIL: %s\n%s\n' "$1" "$output" >&2
    exit 1
  fi
  printf 'PASS: %s\n' "$1"
}

expect_failure() {
  if output=$(bash "$fixture/mise/tasks/marketing/image-budget.sh" 2>&1); then
    printf 'FAIL: %s unexpectedly passed\n' "$1" >&2
    exit 1
  fi
  if ! [[ "$output" == *"$2"* ]]; then
    printf 'FAIL: %s returned the wrong diagnostic\n%s\n' "$1" "$output" >&2
    exit 1
  fi
  printf 'PASS: %s\n' "$1"
}

# Exercise existing, previously omitted, and future directories, with spaces
# and uppercase extensions. Padding preserves the image while testing bytes.
for directory in marketing/images app/images images future/images; do
  mkdir -p "$root/$directory"
  file="$root/$directory/budget test.PNG"
  "${convert[@]}" -size 1x1 xc:white "$file"
  truncate -s $((500 * 1024)) "$file"
  expect_pass "$directory at the static budget"
  truncate -s $((500 * 1024 + 1)) "$file"
  expect_failure "$directory one byte over budget" "$directory/budget test.PNG is 512001 bytes"
  rm "$file"
done

file="$root/images/animation.GIF"
"${convert[@]}" -size 1x1 xc:white "$file"
truncate -s $((3200 * 1024)) "$file"
expect_pass "GIF at its separate budget"
truncate -s $((3200 * 1024 + 1)) "$file"
expect_failure "GIF over budget" "over the 3200 KiB budget"
rm "$file"

file="$root/images/hero-background-test.webp"
"${convert[@]}" -size 1024x1 xc:white "$file"
truncate -s $((20 * 1024)) "$file"
expect_pass "header at its byte and dimension limits"
truncate -s $((20 * 1024 + 1)) "$file"
expect_failure "header one byte over budget" "over the 20 KiB budget"

for dimensions in 1025x1 1x1025; do
  "${convert[@]}" -size "$dimensions" xc:white "$file"
  expect_failure "small compressed header with excessive dimensions ($dimensions)" \
    "over the header limit of 1024 pixels per dimension"
done

printf 'invalid image' > "$file"
expect_failure "unreadable header fails closed" "Cannot read header image dimensions"
rm "$file"

# The exact artwork that escaped the old check must fail if served again.
for original in server/assets/marketing/source-images/hero-background*.webp; do
  cp "$original" "$root/images/"
  expect_failure "original $(basename "$original")" "over the 20 KiB budget"
  rm "$root/images/$(basename "$original")"
done

mkdir -p "$fixture/server/assets/marketing/source-images"
cp server/assets/marketing/source-images/hero-background*.webp \
  "$fixture/server/assets/marketing/source-images/"
expect_pass "regeneration sources outside the served tree"
