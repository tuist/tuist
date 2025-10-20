#!/usr/bin/env bash
#MISE description="Run the CAS worker locally"

set -euo pipefail

ELIXIR_SCRIPT=$(cat <<'ELIXIR'
alias Tuist.Environment

secrets = Environment.decrypt_secrets()
Environment.put_application_secrets(secrets)

vars = %{
  "SERVER_URL" => Environment.app_url([route_type: :app], secrets),
  "TUIST_S3_REGION" => Environment.s3_region(secrets),
  "TUIST_S3_ENDPOINT" => Environment.s3_endpoint(secrets),
  "TUIST_S3_BUCKET_NAME" => Environment.s3_bucket_name(secrets),
  "TUIST_S3_ACCESS_KEY_ID" => Environment.s3_access_key_id(secrets),
  "TUIST_S3_SECRET_ACCESS_KEY" => Environment.s3_secret_access_key(secrets),
  "TUIST_S3_VIRTUAL_HOST" => to_string(Environment.s3_virtual_host(secrets)),
  "TUIST_S3_BUCKET_AS_HOST" => to_string(Environment.s3_bucket_as_host(secrets))
}

Enum.each(vars, fn {key, value} ->
  IO.puts("#{key}=#{value}")
end)
ELIXIR
)

env_output="$(
  cd "$MISE_PROJECT_ROOT/../server" &&
    MIX_ENV=dev MIX_QUIET=1 mix run --no-start -e "$ELIXIR_SCRIPT"
)"

# Parse environment variables without using associative arrays
server_url=""
s3_region=""
s3_endpoint=""
s3_bucket_name=""
s3_access_key_id=""
s3_secret_access_key=""
s3_virtual_host=""
s3_bucket_as_host=""

while IFS='=' read -r key value; do
  [[ -z "${key:-}" ]] && continue
  case "$key" in
    SERVER_URL) server_url="$value" ;;
    TUIST_S3_REGION) s3_region="$value" ;;
    TUIST_S3_ENDPOINT) s3_endpoint="$value" ;;
    TUIST_S3_BUCKET_NAME) s3_bucket_name="$value" ;;
    TUIST_S3_ACCESS_KEY_ID) s3_access_key_id="$value" ;;
    TUIST_S3_SECRET_ACCESS_KEY) s3_secret_access_key="$value" ;;
    TUIST_S3_VIRTUAL_HOST) s3_virtual_host="$value" ;;
    TUIST_S3_BUCKET_AS_HOST) s3_bucket_as_host="$value" ;;
  esac
done <<< "$env_output"

if [[ -z "$server_url" ]]; then
  echo "Unable to determine SERVER_URL" >&2
  exit 1
fi

if [[ -z "$s3_region" || -z "$s3_endpoint" || -z "$s3_bucket_name" || -z "$s3_access_key_id" || -z "$s3_secret_access_key" ]]; then
  echo "Missing required S3 configuration. Ensure secrets are available." >&2
  exit 1
fi

echo $s3_region

pnpm --dir "$MISE_PROJECT_ROOT" exec wrangler dev \
  --config "$MISE_PROJECT_ROOT/wrangler.toml" \
  --var "SERVER_URL:${server_url}" \
  --var "TUIST_S3_REGION:${s3_region}" \
  --var "TUIST_S3_ENDPOINT:${s3_endpoint}" \
  --var "TUIST_S3_BUCKET_NAME:${s3_bucket_name}" \
  --var "TUIST_S3_ACCESS_KEY_ID:${s3_access_key_id}" \
  --var "TUIST_S3_SECRET_ACCESS_KEY:${s3_secret_access_key}" \
  --var "TUIST_S3_VIRTUAL_HOST:${s3_virtual_host}" \
  --var "TUIST_S3_BUCKET_AS_HOST:${s3_bucket_as_host}" \
  "$@"
