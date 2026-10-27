#!/usr/bin/env bash
set -euo pipefail
mkdir -p shard-fixture/lib shard-fixture/test
cat > shard-fixture/mix.exs <<'MIX'
defmodule ShardFixture.MixProject do
  use Mix.Project
  def project, do: [app: :shard_fixture, version: "0.1.0", deps: [{:tuist_ex, path: "../tuist_ex"}], tuist: [project: "tuist/shard-storage-e2e", url: "https://staging.tuist.dev"]]
  def application, do: [extra_applications: [:logger]]
end
MIX
cat > shard-fixture/lib/fixture.ex <<'ELIXIR'
defmodule Fixture do
  def sum(a, b), do: a + b
end
ELIXIR
printf 'ExUnit.start()\n' > shard-fixture/test/test_helper.exs
for n in $(seq 1 8); do
  cat > "shard-fixture/test/fixture_${n}_test.exs" <<ELIXIR
defmodule Fixture.Test${n} do
  use ExUnit.Case, async: true
  test "compiled implementation ${n}", do: assert(Fixture.sum(${n}, 10) == $((n+10)))
end
ELIXIR
done
