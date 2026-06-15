#!/usr/bin/env bash
# Renders generated/{baseline,patched}.conf from nginx/nginx.conf.tmpl, pulling
# the HTTP/2 upload-window values from the live platform chart so the test
# can't drift from what actually deploys. yq runs in a container (no host dep).
#
#   patched.conf  = template + window directives derived from values.yaml
#   baseline.conf = template with the window directives removed (nginx defaults)
set -euo pipefail

cd "$(dirname "$0")"

# Repo-root chart that renders the regional Kura gateway nginx config.
CHART_VALUES="${CHART_VALUES:-../../../../infra/helm/platform/values.yaml}"
GATEWAY_KEY="${GATEWAY_KEY:-kura-us-west-ingress-nginx}"
YQ_IMAGE="${YQ_IMAGE:-mikefarah/yq:4}"

if [ ! -f "$CHART_VALUES" ]; then
  echo "generate-confs: chart values not found at $CHART_VALUES" >&2
  exit 1
fi

# Read one config key from the gateway block. The three regional blocks share
# one anchored node, so any of them yields the deployed values.
cfg() {
  docker run --rm -i "$YQ_IMAGE" \
    ".\"${GATEWAY_KEY}\".controller.config.\"$1\" // \"null\"" < "$CHART_VALUES"
}

cbb="$(cfg client-body-buffer-size)"
streams="$(cfg http2-max-concurrent-streams)"
snippet="$(cfg http-snippet)"

directives=""
if [ "$cbb" != "null" ]; then
  directives+="    client_body_buffer_size ${cbb};"$'\n'
fi
if [ "$streams" != "null" ]; then
  directives+="    http2_max_concurrent_streams ${streams};"$'\n'
fi
if [ "$snippet" != "null" ]; then
  # http-snippet is already raw nginx (e.g. "http2_body_preread_size 4m;").
  directives+="    ${snippet}"$'\n'
fi

mkdir -p generated

# Render the template, replacing the placeholder line with the directives
# (patched) or nothing (baseline). Pure bash so it's portable across BSD/GNU.
render() {
  local mode="$1" out="$2" line
  : > "$out"
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" == *"__WINDOW_DIRECTIVES__"* ]]; then
      if [ "$mode" = "patched" ]; then printf '%s' "$directives" >> "$out"; fi
    else
      printf '%s\n' "$line" >> "$out"
    fi
  done < nginx/nginx.conf.tmpl
}
render patched generated/patched.conf
render baseline generated/baseline.conf

echo "generate-confs: from ${CHART_VALUES} [${GATEWAY_KEY}]"
echo "  client-body-buffer-size=${cbb}  http2-max-concurrent-streams=${streams}  http-snippet=\"${snippet}\""
