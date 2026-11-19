#!/usr/bin/env bash
# Build-time checks for a vendor's public Java cacerts, never private identities.
set -euo pipefail

[[ $# -eq 2 && ( "$1" == check || "$1" == filter ) ]] || {
  echo "usage: $0 check|filter PUBLIC_CACERTS" >&2
  exit 2
}
mode="$1"
store="$(realpath "$2")"
links="$(stat -c %h "$store" 2>/dev/null || stat -f %l "$store")"
[[ "$links" == 1 ]] || { echo "refusing a hardlinked or unverifiable Java store" >&2; exit 1; }
helper="$(cd "$(dirname "$0")" && pwd)/pem-store.sh"
work="$(mktemp -d)"
staged=""
trap 'rm -rf "$work"; if [[ -n "$staged" ]]; then rm -f "$staged"; fi' EXIT

list_store() {
  keytool -J-Duser.language=en -J-Duser.country=US -list -rfc \
    -keystore "$1" -storepass changeit > "$2"
  # Refuse the entire store if it contains an identity or an unknown entry type.
  # This helper is intentionally limited to password-changeit public SDK stores.
  grep -q '^Entry type: trustedCertEntry$' "$2" || {
    echo "empty or unsupported public Java store" >&2; exit 1;
  }
  if grep '^Entry type:' "$2" | grep -vFx 'Entry type: trustedCertEntry' >&2; then
    echo "refusing to modify a private/unsupported Java entry" >&2
    exit 1
  fi
}

list_store "$store" "$work/before.pem"
if [[ "$mode" == check ]]; then
  bash "$helper" check "$work/before.pem"
  exit
fi

staged="$(mktemp "${store}.tuist.XXXXXX")"
cp -p "$store" "$staged"
awk '/^Alias name: / { print substr($0, 13) }' "$work/before.pem" > "$work/aliases"
[[ -s "$work/aliases" ]] || { echo "cannot establish Java aliases" >&2; exit 1; }
while IFS= read -r alias; do
  [[ -n "$alias" ]] || { echo "empty Java alias" >&2; exit 1; }
  keytool -J-Duser.language=en -J-Duser.country=US -exportcert -rfc \
    -keystore "$staged" -storepass changeit -alias "$alias" > "$work/entry.pem"
  mkdir "$work/blocked"
  bash "$helper" extract-blocked "$work/entry.pem" "$work/blocked"
  if [[ -n "$(find "$work/blocked" -type f -name '*.pem' -print -quit)" ]]; then
    keytool -J-Duser.language=en -J-Duser.country=US -delete \
      -keystore "$staged" -storepass changeit -alias "$alias"
  fi
  rm -rf "$work/blocked"
done < "$work/aliases"

list_store "$staged" "$work/after.pem"
bash "$helper" check "$work/after.pem"
# Stage beside the resolved target: preserve symlinks/metadata and replace only
# after keytool and the independent PEM postcondition have both succeeded.
mv -f "$staged" "$store"
staged=""
