#!/usr/bin/env bash
# Validate the release image through Compose and a disposable Kubernetes cluster.
set -euo pipefail
image_version=${ATLAS_TEST_VERSION:-deployment-test}
work=$(mktemp -d)
cluster="atlas-check-$$"
compose_project="atlas-check-$$"
root=$(cd "$(dirname "$0")/../.." && pwd)
export KUBECONFIG="$work/kubeconfig"
forward_pid=""
cleanup() {
  result=$?
  if [ "$result" -ne 0 ]; then
    docker compose --project-name "$compose_project" --project-directory "$work" logs --tail 80 || true
    if [ -s "$KUBECONFIG" ]; then
      kubectl get pods || true
      kubectl logs deployment/atlas-atlas --all-containers --tail=80 || true
    fi
  fi
  if [ -n "$forward_pid" ]; then kill "$forward_pid" >/dev/null 2>&1 || true; fi
  docker compose --project-name "$compose_project" --project-directory "$work" down --volumes >/dev/null 2>&1 || true
  kind delete cluster --name "$cluster" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
check_schedulers() {
  docker run --rm --cpus "$1" --env EXPECTED_SCHEDULERS="$2" --env ERL_FLAGS="${3:-}" \
    --entrypoint /bin/sh "ghcr.io/tuist/atlas:$image_version" -c '
      set -- /app/releases/*/start_clean.boot
      /app/erts-*/bin/erl -boot "${1%.boot}" -boot_var RELEASE_LIB /app/lib -noshell -eval '\''
        Expected = list_to_integer(os:getenv("EXPECTED_SCHEDULERS")),
        Actual = erlang:system_info(schedulers_online),
        io:format("Expected ~p active schedulers, got ~p~n", [Expected, Actual]),
        case Actual of Expected -> halt(0); _ -> halt(1) end.
      '\''
    '
}
check_schedulers 1 1
check_schedulers 2 2
check_schedulers 1 3 '+S 3:3'
cp "$root/atlas/compose.yaml" "$work/compose.yaml"
mkdir "$work/deploy"
cp "$root/atlas/deploy/Caddyfile" "$work/deploy/Caddyfile"
cat > "$work/.env" <<ENV
ATLAS_VERSION=$image_version
ATLAS_HOST=localhost
ATLAS_HTTP_PORT=18080
ATLAS_HTTPS_PORT=18443
ATLAS_ALLOWED_EMAIL_DOMAIN=example.org
POSTGRES_PASSWORD=$(openssl rand -hex 32)
SECRET_KEY_BASE=$(openssl rand -hex 64)
GUARDIAN_SECRET_KEY=$(openssl rand -hex 64)
ENCRYPTION_KEY=$(openssl rand -base64 32)
MCP_PROXY_SERVERS=[]
ENV
compose=(docker compose --project-name "$compose_project" --project-directory "$work")
"${compose[@]}" config --quiet
"${compose[@]}" up -d
for attempt in $(seq 1 120); do
  if curl --silent --fail --insecure https://localhost:18443/ready >/dev/null; then break; fi
  container=$("${compose[@]}" ps -q atlas)
  if [ -n "$container" ] && [ "$(docker inspect --format '{{.RestartCount}}' "$container")" -gt 3 ]; then
    echo "Atlas repeatedly failed to start" >&2
    exit 1
  fi
  if [ "$attempt" = 120 ]; then exit 1; fi
  sleep 2
done
curl --fail --insecure https://localhost:18443/docs/self-hosting > "$work/compose-docs.html"
grep -q 'Docker Compose' "$work/compose-docs.html"
if [ -n "${ATLAS_SCREENSHOT_DIR:-}" ]; then
  mkdir -p "$ATLAS_SCREENSHOT_DIR"
  python3 - "$ATLAS_SCREENSHOT_DIR" "${ATLAS_CHROME_PATH:-google-chrome}" "$work" <<'PYTHON'
import pathlib, subprocess, sys, time
output, chrome, temporary = pathlib.Path(sys.argv[1]).resolve(), sys.argv[2], pathlib.Path(sys.argv[3])
for name, size, extra in [
    ("desktop", "1440,1100", []),
    ("mobile", "390,844", []),
    ("dark", "1440,1100", ["--force-dark-mode"]),
]:
    screenshot = output / (name + ".png")
    process = subprocess.Popen([
        chrome, "--headless", "--no-sandbox", "--disable-gpu",
        "--ignore-certificate-errors", "--hide-scrollbars",
        "--no-first-run", "--no-default-browser-check",
        "--user-data-dir=" + str(temporary / ("profile-" + name)),
        "--window-size=" + size,
        "--screenshot=" + str(screenshot),
        *extra, "https://localhost:18443/docs/self-hosting",
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        deadline = time.monotonic() + 30
        while not screenshot.exists() or screenshot.stat().st_size < 1000:
            if process.poll() is not None or time.monotonic() > deadline:
                raise RuntimeError("Chrome did not capture " + name)
            time.sleep(0.1)
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
PYTHON
fi
"${compose[@]}" down --volumes

chart="$root/infra/helm/atlas"
helm lint "$chart"
helm template standalone "$chart" > "$work/standalone.yaml"
helm template atlas "$chart" --values "$chart/values-managed-production.yaml" > "$work/managed.yaml"
if grep -Eq 'kind: (ExternalSecret|Cluster)|tuist-server-token|atlas.tuist.dev' "$work/standalone.yaml"; then
  echo 'Standalone chart unexpectedly depends on managed infrastructure' >&2
  exit 1
fi
helm package "$chart" --version 0.0.0 --app-version "$image_version" --destination "$work"
if tar -tzf "$work/atlas-0.0.0.tgz" | grep -q values-managed; then
  echo 'Published chart includes managed configuration' >&2
  exit 1
fi
kind create cluster --name "$cluster" --wait 120s
kind load docker-image "ghcr.io/tuist/atlas:$image_version" --name "$cluster"
cp "$work/.env" "$work/kubernetes.env"
printf 'DATABASE_URL=ecto://atlas:atlas@postgres:5432/atlas\n' >> "$work/kubernetes.env"
kubectl create secret generic atlas-app --from-env-file="$work/kubernetes.env"
kubectl create deployment postgres --image=postgres:18.0
kubectl set env deployment/postgres POSTGRES_USER=atlas POSTGRES_PASSWORD=atlas POSTGRES_DB=atlas
kubectl expose deployment postgres --port=5432
kubectl rollout status deployment/postgres --timeout=120s
# Wait for database initialization as well as container startup.
kubectl exec deployment/postgres -- sh -c 'until pg_isready -U atlas -d atlas; do sleep 1; done'
helm upgrade --install atlas "$work/atlas-0.0.0.tgz" \
  --set appSecretName=atlas-app --set image.pullPolicy=Never \
  --set env.ATLAS_ALLOWED_EMAIL_DOMAIN=example.org --wait --timeout 10m
kubectl port-forward service/atlas-atlas 18081:80 > "$work/port-forward.log" 2>&1 &
forward_pid=$!
for attempt in $(seq 1 30); do
  if curl --silent --fail http://localhost:18081/ready >/dev/null; then break; fi
  sleep 1
done
curl --fail http://localhost:18081/ready
curl --fail -H 'X-Forwarded-Proto: https' http://localhost:18081/docs/self-hosting > "$work/helm-docs.html"
grep -q 'Docker Compose' "$work/helm-docs.html"
kill "$forward_pid"
echo 'Compose and Helm deployments passed readiness and documentation checks.'
