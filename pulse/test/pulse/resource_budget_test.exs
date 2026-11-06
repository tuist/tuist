defmodule Pulse.ResourceBudgetTest do
  use Pulse.Test.Case, async: true

  alias Pulse.ResourceBudget
  alias Pulse.Storage.S3.ManifestCache

  doctest ResourceBudget

  @runtime Path.expand("../../config/runtime.exs", __DIR__)

  test "derived envelopes fit their budget above the reserve, and small nodes keep minimum slots" do
    for budget <- [1024, 1536, 2048, 4096, 16_384, 1_048_576] do
      envelope = ResourceBudget.derive(budget)
      used = envelope.ingest_slots * 32 + (envelope.query_slots + 2) * envelope.query_heap_mb
      assert used <= budget - 256, inspect(envelope)
    end

    assert %{ingest_slots: 2, query_slots: 1, query_heap_mb: 32} = ResourceBudget.derive(256)
    assert %{ingest_slots: 28, query_slots: 5, query_heap_mb: 128} = ResourceBudget.derive(2048)
    assert %{ingest_slots: 256, query_slots: 64, query_heap_mb: 128} = ResourceBudget.derive(1_048_576)
  end

  @tag :tmp_dir
  test "cgroup limits are read from v2, then v1, and unlimited means none", %{tmp_dir: dir} do
    assert ResourceBudget.cgroup_limit_mb(dir) == nil
    File.mkdir_p!(Path.join(dir, "memory"))
    File.write!(Path.join(dir, "memory/memory.limit_in_bytes"), "9223372036854771712\n")
    assert ResourceBudget.cgroup_limit_mb(dir) == nil
    File.write!(Path.join(dir, "memory/memory.limit_in_bytes"), "536870912\n")
    assert ResourceBudget.cgroup_limit_mb(dir) == 512
    File.write!(Path.join(dir, "memory.max"), "max\n")
    assert ResourceBudget.cgroup_limit_mb(dir) == 512
    File.write!(Path.join(dir, "memory.max"), "1073741824\n")
    assert ResourceBudget.cgroup_limit_mb(dir) == 1024
  end

  test "a memory budget sizes slots unless a setting is explicit" do
    Pulse.Runtime.put_env("PULSE_MEMORY_BUDGET_MB", "1024")
    config = Config.Reader.read!(@runtime, env: :test, target: :host)
    assert config[:pulse][Pulse.IngestAdmission][:max_concurrent] == 12
    assert config[:pulse][Pulse.QueryRunner][:max_interactive] == 3
    assert config[:pulse][Pulse.QueryRunner][:max_global] == 5
    assert config[:pulse][Pulse.QueryRunner][:max_heap_words] == div(76 * 1_048_576, 8)
    assert config[:pulse][Pulse.ResourceBudget][:budget_mb] == 1024
    # Memory pressure compares against the same explicit budget.
    assert config[:pulse][Pulse.MemoryPressure] == [high_percent: 85, limit: 1024 * 1_048_576]

    Pulse.Runtime.put_env("PULSE_MEMORY_PRESSURE_PERCENT", "0")
    assert Config.Reader.read!(@runtime, env: :test, target: :host)[:pulse][Pulse.MemoryPressure][:limit] == nil
    Pulse.Runtime.delete_env("PULSE_MEMORY_PRESSURE_PERCENT")

    Pulse.Runtime.put_env("PULSE_INGEST_MAX_CONCURRENT_REQUESTS", "40")
    Pulse.Runtime.put_env("PULSE_QUERY_MAX_HEAP_MB", "64")
    config = Config.Reader.read!(@runtime, env: :test, target: :host)
    assert config[:pulse][Pulse.IngestAdmission][:max_concurrent] == 40
    assert config[:pulse][Pulse.QueryRunner][:max_heap_words] == div(64 * 1_048_576, 8)

    Pulse.Runtime.put_env("PULSE_MEMORY_BUDGET_MB", "100")
    assert_raise RuntimeError, fn -> Config.Reader.read!(@runtime, env: :test, target: :host) end
  end

  test "without a budget outside production, the fixed defaults apply" do
    config = Config.Reader.read!(@runtime, env: :test, target: :host)
    assert config[:pulse][Pulse.IngestAdmission][:max_concurrent] == 32
    assert config[:pulse][Pulse.QueryRunner][:max_interactive] == 3
    assert config[:pulse][Pulse.ResourceBudget][:budget_mb] == nil
    assert config[:pulse][Pulse.MemoryPressure][:limit] == nil
    assert config[:pulse][ManifestCache][:max_bytes] == 134_217_728
  end
end
