#!/bin/sh
# CI pod only. Preserve shared-bucket privacy/lifecycle gates in every environment.
set -eu
case "$DEPLOY_ENV" in staging|canary|production) ;; *) exit 1 ;; esac
case "$CHECK_RUN" in ''|*[!a-zA-Z0-9-]*) exit 1 ;; esac
prefix=pulse
bucket="tuist-pulso-$DEPLOY_ENV"
url="https://t3.storage.dev/$bucket"
key="$prefix/ci-preflight/$CHECK_RUN"
work=$(mktemp -d)
created=false
step=
code=
# curl prints 000 when it cannot connect; the failing step reports it.
request() {
  curl --silent --max-time 30 --aws-sigv4 'aws:amz:auto:s3' \
    --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
    --output "$work/response" --write-out '%{http_code}' "$@" || :
}
cleanup() {
  status=$?
  if [ "$status" != 0 ] && [ -n "$step" ]; then
    # Only the S3 error code, never the message or request details.
    s3=$(sed -n 's:.*<Code>\([A-Za-z]*\)</Code>.*:\1:p' "$work/response" 2>/dev/null | head -n1)
    printf 'FAIL: %s (HTTP %s, S3 %s)\n' "$step" "${code:-none}" "${s3:-none}" >&2
  fi
  if [ "$created" = true ]; then
    code=$(request -X DELETE "$url/$key") || code=000
    if [ "$code" != 204 ] && [ "$code" != 200 ]; then
      echo 'FAIL: could not remove the run-scoped storage probe' >&2
      status=1
    fi
  fi
  rm -rf "$work"
  exit "$status"
}
trap cleanup EXIT
step="read the bucket lifecycle"
code=$(request "$url?lifecycle")
if [ "$code" = 404 ]; then
  grep -q '<Code>NoSuchLifecycleConfiguration</Code>' "$work/response"
elif [ "$code" = 200 ]; then
  grep -q 'LifecycleConfiguration' "$work/response"
  if grep -q '<Rule[ >]' "$work/response"; then
    echo 'FAIL: shared bucket has lifecycle rules; review isolation before deploying' >&2
    exit 1
  fi
else
  error=Unknown
  for known in AccessDenied NotImplemented InvalidAccessKeyId SignatureDoesNotMatch AuthorizationHeaderMalformed PermanentRedirect NoSuchBucket; do
    if grep -Fq "<Code>$known</Code>" "$work/response" 2>/dev/null; then error=$known; break; fi
  done
  printf 'FAIL: shared bucket lifecycle could not be verified (HTTP %s, S3 %s)\n' "$code" "$error" >&2
  exit 1
fi
step="list $prefix/"
code=$(request "$url?list-type=2&prefix=$prefix%2F&max-keys=1")
[ "$code" = 200 ]
grep -q 'ListBucketResult' "$work/response"
printf 'pulse-preflight-17' > "$work/payload"
created=true
step="write the probe object"
code=$(request -X PUT --data-binary "@$work/payload" "$url/$key")
[ "$code" = 200 ]
step="read the probe object back"
code=$(request "$url/$key")
[ "$code" = 200 ]
cmp -s "$work/payload" "$work/response"
step=
code=$(curl --silent --max-time 30 --output "$work/anonymous" --write-out '%{http_code}' "$url/$key")
case "$code" in 401|403|404) ;; *) echo 'FAIL: probe object is anonymously readable or privacy is unknown' >&2; exit 1 ;; esac
echo 'PASS: no bucket lifecycle rules, prefix list/write/read access and private probe object'
# Report, never gate: what would let us recover objects a GC bug deleted.
# Tigris marks snapshot-enabled buckets on HeadBucket, answers
# GetBucketVersioning, and refuses a soft-delete restore with "Soft-delete is
# not enabled" when it is off (a key with no deleted version is a 404 then).
code=$(request --head "$url")
snapshots=$(tr -d '\r' < "$work/response" | sed -n 's/^[Xx]-[Tt]igris-[Ee]nable-[Ss]napshot: *//p' | head -n1)
[ "$code" = 200 ] || snapshots="unknown (HTTP $code)"
code=$(request "$url?versioning")
versioning=$(sed -n 's:.*<Status>\([A-Za-z]*\)</Status>.*:\1:p' "$work/response" | head -n1)
if [ "$code" != 200 ]; then versioning="unknown (HTTP $code)"; fi
code=$(request -X POST --data '' -H 'X-Tigris-Restore-Type: soft-delete' "$url/$prefix/ci-preflight/never-written-$CHECK_RUN?restore")
if grep -q 'Soft-delete is not enabled' "$work/response" 2>/dev/null; then
  soft_delete=disabled
elif [ "$code" = 404 ]; then
  soft_delete=enabled
else
  soft_delete="unknown (HTTP $code, S3 $(sed -n 's:.*<Code>\([A-Za-z]*\)</Code>.*:\1:p' "$work/response" | head -n1))"
fi
echo "INFO: $bucket data protection: snapshots=${snapshots:-false} versioning=${versioning:-never enabled} soft_delete=$soft_delete"
