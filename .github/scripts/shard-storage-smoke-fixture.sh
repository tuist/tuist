#!/usr/bin/env bash
# Writes the minimal Mix project linux-shard-storage-smoke.yml shards.
set -euo pipefail

directory="$1"
mkdir -p "$directory/lib" "$directory/test"

cat > "$directory/mix.exs" <<'MIX'
defmodule ShardSmoke.MixProject do
  use Mix.Project

  def project do
    [app: :shard_smoke, version: "0.1.0", deps: [{:tuist_ex, path: "..", runtime: false}]]
  end

  def application, do: [extra_applications: [:logger]]
end
MIX

cat > "$directory/lib/shard_smoke.ex" <<'LIB'
defmodule ShardSmoke do
  def double(value), do: value * 2
end
LIB

echo 'ExUnit.start()' > "$directory/test/test_helper.exs"

for index in 1 2 3 4; do
  cat > "$directory/test/shard_smoke_${index}_test.exs" <<TEST
defmodule ShardSmoke${index}Test do
  use ExUnit.Case, async: true

  test "doubles ${index}" do
    assert ShardSmoke.double(${index}) == ${index} * 2
  end
end
TEST
done
