#!/usr/bin/env bash
#MISE description="Rehearse a three-member Keeper disk migration in disposable Docker containers"
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
WORK=$(mktemp -d)
prefix="tuist-keeper-test-$$"
image="${KEEPER_TEST_IMAGE:-clickhouse/clickhouse-server:26.3}"
cleanup() {
  for i in 0 1 2; do
    docker rm -f "$prefix-$i" >/dev/null 2>&1 || true
    docker volume rm "$prefix-cloud-$i" "$prefix-local-$i" >/dev/null 2>&1 || true
  done
  docker network rm "$prefix" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT
docker network create "$prefix" >/dev/null
cat > "$WORK/keeper.xml" <<'XML'
<clickhouse>
  <logger><level>warning</level><console>true</console></logger>
  <listen_host>0.0.0.0</listen_host>
  <keeper_server>
    <tcp_port>9181</tcp_port>
    <server_id from_env="KEEPER_SERVER_ID"/>
    <log_storage_path>/var/lib/clickhouse-keeper/log</log_storage_path>
    <snapshot_storage_path>/var/lib/clickhouse-keeper/snapshots</snapshot_storage_path>
    <raft_configuration>
      <server><id>1</id><hostname>keeper-0</hostname><port>9234</port></server>
      <server><id>2</id><hostname>keeper-1</hostname><port>9234</port></server>
      <server><id>3</id><hostname>keeper-2</hostname><port>9234</port></server>
    </raft_configuration>
  </keeper_server>
</clickhouse>
XML
start_member() {
  local i="$1" disk="$2"
  docker run -d --name "$prefix-$i" --hostname "keeper-$i" \
    --network "$prefix" --network-alias "keeper-$i" --memory 1g \
    -e "KEEPER_SERVER_ID=$((i + 1))" \
    -v "$WORK/keeper.xml:/etc/keeper.xml:ro" \
    -v "$prefix-$disk-$i:/var/lib/clickhouse-keeper" \
    --entrypoint clickhouse-keeper "$image" --config-file /etc/keeper.xml >/dev/null
}
query() {
  docker exec "$prefix-$1" clickhouse keeper-client --host 127.0.0.1 --port 9181 --query "$2"
}
wait_value() {
  local i="$1" expected="$2"
  for ((attempt = 0; attempt < 45; attempt++)); do
    if [[ "$(query "$i" 'get /migration-test' 2>/dev/null)" == "$expected" ]]; then return; fi
    sleep 1
  done
  docker logs "$prefix-$i" >&2
  echo "Member $i did not recover value $expected" >&2
  return 1
}
for i in 0 1 2; do start_member "$i" cloud; done
created=false
for ((attempt = 0; attempt < 45; attempt++)); do
  if query 0 'create /migration-test before' >/dev/null 2>&1; then created=true; break; fi
  sleep 1
done
[[ "$created" == true ]]
for i in 0 1 2; do wait_value "$i" before; done
for i in 0 1 2; do
  peer=$(((i + 1) % 3))
  docker stop --time 120 "$prefix-$i" >/dev/null
  # A successful write while this member is stopped proves surviving quorum.
  query "$peer" "set /migration-test during-$i" >/dev/null
  docker run --rm --hostname "keeper-$i" --entrypoint /bin/bash \
    -v "$prefix-cloud-$i:/legacy:ro" -v "$prefix-local-$i:/local" \
    -v "$ROOT/infra/helm/tuist/files/keeper-copy-state.sh:/copy-state.sh:ro" \
    "$image" /copy-state.sh
  docker rm "$prefix-$i" >/dev/null
  start_member "$i" local
  for member in 0 1 2; do wait_value "$member" "during-$i"; done
  printf 'Member %s migrated; all members caught up.\n' "$i"
done
# Remove every old disk, then restart each member to verify local durability.
for i in 0 1 2; do docker volume rm "$prefix-cloud-$i" >/dev/null; done
query 0 'set /migration-test local-only' >/dev/null
for i in 0 1 2; do
  docker restart --time 120 "$prefix-$i" >/dev/null
  wait_value "$i" local-only
done
printf 'Three-member migration preserved metadata, quorum writes and local-only restarts.\n'
