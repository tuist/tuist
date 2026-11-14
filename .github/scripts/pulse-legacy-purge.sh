#!/usr/bin/env bash
# Deletes the custom Elixir Pulse's prefixes from one bucket (BUCKET), with
# the AWS CLI's ambient credentials. Lists 1,000 keys per page and deletes each
# page with one DeleteObjects request, PARALLEL pages at a time; rerunning
# resumes where a previous run stopped. Everything else in the bucket stays.
set -euo pipefail
: "${BUCKET:?bucket required}"
parallel=${PARALLEL:-16}
legacy='^(tenants|system|usage|auth|\.pulse)/$'
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

top() {
  aws s3api list-objects-v2 --bucket "$BUCKET" --delimiter / --no-paginate --output json |
    jq -r '(.CommonPrefixes // [])[].Prefix, (.Contents // [])[].Key'
}

delete_page() {
  local out
  out=$(aws s3api delete-objects --bucket "$BUCKET" --delete "file://$1" --output json)
  # Quiet mode prints nothing, or only the keys that failed.
  if [[ -n "$out" ]] && jq -e '(.Errors // []) | length > 0' <<< "$out" > /dev/null; then
    jq -c '.Errors[:3]' <<< "$out" >&2
    return 1
  fi
  rm -f "$1"
}
export -f delete_page
export BUCKET

# Writes one DeleteObjects body per page and prints its path.
pages() {
  local prefix=$1 token='' n=0 page
  while :; do
    local args=(--bucket "$BUCKET" --prefix "$prefix" --max-keys 1000 --no-paginate --output json)
    [[ -n "$token" ]] && args+=(--continuation-token "$token")
    page=$(aws s3api list-objects-v2 "${args[@]}")
    if jq -e '(.Contents // []) | length > 0' <<< "$page" > /dev/null; then
      n=$((n + 1))
      jq -c '{Objects: [.Contents[] | {Key}], Quiet: true}' <<< "$page" > "$work/page-$n.json"
      jq '.Contents | length' <<< "$page" >> "$work/counts"
      echo "$work/page-$n.json"
      if (( n % 100 == 0 )); then echo "$prefix: $n pages listed" >&2; fi
    fi
    token=$(jq -r '.NextContinuationToken // empty' <<< "$page")
    [[ -n "$token" ]] || break
  done
}

echo "### $BUCKET"
echo '| Prefix | Objects deleted |'
echo '|---|---|'
while IFS= read -r prefix; do
  : > "$work/counts"
  pages "$prefix" | xargs -r -P "$parallel" -I{} bash -c 'delete_page "$1"' _ {}
  echo "| \`$prefix\` | $(awk '{s += $1} END {print s + 0}' "$work/counts") |"
done < <(top | grep -E "$legacy" || true)
left=$(top)
if grep -Eq "$legacy" <<< "$left"; then
  echo "Legacy prefixes remain in $BUCKET" >&2
  exit 1
fi
echo "PASS: no legacy Pulse objects in $BUCKET. Kept: $(tr '\n' ' ' <<< "$left")"
