#!/usr/bin/env bash
#MISE description="Seed a preview test account and wire it to the preview's KuraInstance. Called by preview-up.sh (local kind) and the preview-deploy workflow (managed cluster). Idempotent."
#USAGE flag "--namespace <ns>" help="Kubernetes namespace where the preview server runs" default="default"

# Env-driven inputs (so the same script works for both kind and the
# preview-deploy workflow):
#
#   PREVIEW_ACCOUNT_HANDLE  Account handle to create (matches the
#                           KuraInstance's tenantID so the Lua hook's
#                           strict tenant check passes). Default: preview.
#   KURA_ENDPOINT_URL       Internal URL clients use to reach the preview's
#                           Kura runtime. Stored on the account's
#                           kura_servers row.
#   RELEASE_NAME            Helm release name; used to find the server pod.
#   PREVIEW_USER_PASSWORD   Password the seeded user gets. Default:
#                           preview-temp-password.
#
# Required tools: kubectl. The script execs into the server pod, so
# kubectl needs cluster access; nothing leaves the cluster.

set -euo pipefail

NAMESPACE="${usage_namespace:-default}"
PREVIEW_ACCOUNT_HANDLE="${PREVIEW_ACCOUNT_HANDLE:-preview}"
PREVIEW_USER_EMAIL="${PREVIEW_USER_EMAIL:-${PREVIEW_ACCOUNT_HANDLE}@preview.tuist.dev}"
PREVIEW_USER_PASSWORD="${PREVIEW_USER_PASSWORD:-preview-temp-password}"
KURA_ENDPOINT_URL="${KURA_ENDPOINT_URL:?KURA_ENDPOINT_URL must be set}"
RELEASE_NAME="${RELEASE_NAME:?RELEASE_NAME must be set}"

SERVER_POD_LABEL="app.kubernetes.io/instance=${RELEASE_NAME},app.kubernetes.io/component=server"

echo "==> Locating server pod (ns=${NAMESPACE}, release=${RELEASE_NAME})..."
SERVER_POD="$(kubectl -n "$NAMESPACE" get pod -l "$SERVER_POD_LABEL" \
  -o jsonpath='{.items[0].metadata.name}')"
if [ -z "$SERVER_POD" ]; then
  echo "ERROR: no server pod found matching label '$SERVER_POD_LABEL'" >&2
  exit 1
fi
echo "    Found $SERVER_POD"

# Pipe a small Elixir script to `tuist eval` running inside the release.
# Idempotent — every step checks for existing state first. `kubectl exec`
# doesn't carry a `--env` flag (that's a `kubectl run`/`debug` thing), so
# we prepend `env VAR=val ...` to set them for the `tuist eval` process.
echo "==> Seeding preview account '${PREVIEW_ACCOUNT_HANDLE}' + Kura endpoint..."
kubectl -n "$NAMESPACE" exec -i "$SERVER_POD" -c server \
  -- env \
       "PREVIEW_ACCOUNT_HANDLE=$PREVIEW_ACCOUNT_HANDLE" \
       "PREVIEW_USER_EMAIL=$PREVIEW_USER_EMAIL" \
       "PREVIEW_USER_PASSWORD=$PREVIEW_USER_PASSWORD" \
       "PREVIEW_KURA_URL=$KURA_ENDPOINT_URL" \
       /app/bin/tuist eval - <<'EOF'
require Logger
alias Tuist.Accounts

handle = System.get_env("PREVIEW_ACCOUNT_HANDLE")
email = System.get_env("PREVIEW_USER_EMAIL")
password = System.get_env("PREVIEW_USER_PASSWORD")
endpoint_url = System.get_env("PREVIEW_KURA_URL")

user =
  case Accounts.get_user_by_email(email) do
    nil ->
      Logger.info("preview-seed: creating user " <> email)
      {:ok, user} = Accounts.create_user(email, handle: handle, password: password)
      user

    user ->
      Logger.info("preview-seed: reusing existing user " <> email)
      user
  end

account = Accounts.get_account_from_user(user)
Logger.info("preview-seed: account handle " <> account.name)

# create_account_cache_endpoint enforces uniqueness on url+technology,
# so the upsert is implicit — we just swallow the constraint error on
# re-runs.
case Accounts.create_account_cache_endpoint(account, %{url: endpoint_url, technology: :kura}) do
  {:ok, _} -> Logger.info("preview-seed: created kura cache endpoint " <> endpoint_url)
  {:error, _} -> Logger.info("preview-seed: kura cache endpoint already present")
end

FunWithFlags.enable(:kura_cache, for_actor: account)
Logger.info("preview-seed: kura_cache feature flag enabled for " <> account.name)
EOF
echo "    Seeded account=${PREVIEW_ACCOUNT_HANDLE} endpoint=${KURA_ENDPOINT_URL}"
