defmodule Pulse.Storage.S3.MetricQueryIntegrationTest do
  use Pulse.Test.Case, async: true

  alias Pulse.ObjectStore
  alias Pulse.PromQL.Evaluator
  alias Pulse.Record.MetricSample
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.Memory
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.ManifestCache
  alias Pulse.Storage.S3.ManifestOwner
  alias Pulse.Storage.S3.ManifestSupervision

  @moduletag :integration

  setup do
    config = %{
      bucket: System.get_env("PULSE_S3_BUCKET", "pulse"),
      endpoint: System.get_env("PULSE_S3_ENDPOINT", "http://localhost:11100"),
      region: "us-east-1",
      access_key_id: "rustfsadmin",
      secret_access_key: "rustfsadmin",
      allow_http: true,
      refresh_stale_ms: 0
    }

    Runtime.put_env(:pulse, S3, config)
    start_supervised!(ManifestSupervision)
    tenant = "metric-query-#{System.unique_integer([:positive])}"

    on_exit(
      Runtime.capture(fn ->
        case ObjectStore.list(config, "tenants/#{tenant}/") do
          {:ok, keys} -> Enum.each(keys, &ObjectStore.delete(config, &1))
          _ -> :ok
        end
      end)
    )

    {:ok, config: config, tenant: tenant}
  end

  defp samples(name, instance \\ "a") do
    for seconds <- [10, 20] do
      %MetricSample{
        timestamp_ns: seconds * 1_000_000_000,
        value: seconds * 1.0,
        labels: %{"__name__" => name, "job" => "api", "instance" => instance}
      }
    end
  end

  test "pruning skips corrupt irrelevant objects and survives manifest reload", %{config: config, tenant: tenant} do
    assert :ok = S3.append(:metrics, tenant, samples("wanted"))
    assert :ok = S3.append(:metrics, tenant, samples("other"))
    {:ok, entry} = ManifestOwner.ensure_loaded(tenant, "metrics", config)
    other = Enum.find(entry.manifest.segments, &(&1.metric_names == ["other"]))
    assert {:ok, _} = ObjectStore.put(config, other.key, "not parquet")
    {:ok, owner} = ManifestOwner.ensure_started(tenant, "metrics", config)
    :ok = GenServer.stop(owner)
    ManifestCache.drop(tenant, "metrics")
    assert {:ok, found} = S3.query(:metrics, tenant, matchers: [{"__name__", :eq, "wanted"}])
    assert length(found) == 2
    assert {:error, _} = S3.query(:metrics, tenant, [])

    # Old manifests have no summary. They must scan the object, which exposes
    # the corruption instead of incorrectly treating an unknown name set as empty.
    {:ok, entry} = ManifestOwner.ensure_loaded(tenant, "metrics", config)
    legacy = %{entry.manifest | segments: Enum.map(entry.manifest.segments, &%{&1 | metric_names: nil})}

    assert {:ok, _} =
             ObjectStore.put(
               config,
               Manifest.manifest_key(tenant, "metrics"),
               IO.iodata_to_binary(Manifest.encode(legacy))
             )

    # refresh_stale_ms: 0 forces a conditional manifest read.
    assert {:error, _} = S3.query(:metrics, tenant, matchers: [{"__name__", :eq, "wanted"}])
  end

  test "an hour-long range fits the default object budget at fifteen-second ingest intervals", %{tenant: tenant} do
    for i <- 1..300 do
      record = %MetricSample{timestamp_ns: i * 15_000_000_000, value: i * 1.0, labels: %{"__name__" => "up"}}
      assert :ok = S3.append(:metrics, tenant, [record])
    end

    Runtime.put_env(:pulse, Storage, adapter: S3)

    assert {:ok, result} =
             Evaluator.query("up", tenant, %{
               start_ts_ns: 900_000_000_000,
               end_ts_ns: 4_500_000_000_000,
               step_ns: 60_000_000_000
             })

    assert [%{"values" => values}] = result["data"]["result"]
    assert length(values) == 61
  end

  test "actual bytes are checked when older manifests omit object sizes", %{tenant: tenant, config: config} do
    assert :ok = S3.append(:metrics, tenant, samples("wanted"))
    {:ok, entry} = ManifestOwner.ensure_loaded(tenant, "metrics", config)
    manifest = %{entry.manifest | segments: Enum.map(entry.manifest.segments, &%{&1 | byte_size: 0})}

    assert {:ok, _} =
             ObjectStore.put(
               config,
               Manifest.manifest_key(tenant, "metrics"),
               IO.iodata_to_binary(Manifest.encode(manifest))
             )

    assert {:error, :query_scan_limit} =
             S3.query(:metrics, tenant, max_scan_bytes: 1, matchers: [{"job", :re, "absent"}])
  end

  test "sample budgets span multiple segments", %{tenant: tenant} do
    assert :ok = S3.append(:metrics, tenant, samples("wanted", "a"))
    assert :ok = S3.append(:metrics, tenant, samples("wanted", "b"))
    assert {:error, :query_sample_limit} = S3.query(:metrics, tenant, max_records: 3)
    assert {:ok, found} = S3.query(:metrics, tenant, max_records: 4)
    assert length(found) == 4

    for budget <- [[max_scan_segments: 1], [max_scan_bytes: 1]] do
      assert {:error, :query_scan_limit} = S3.query(:metrics, tenant, [{:matchers, [{"job", :re, "absent"}]} | budget])
    end

    # The rows budget counts matched rows: none here, four without matchers.
    assert {:ok, []} = S3.query(:metrics, tenant, matchers: [{"job", :re, "absent"}], max_scan_rows: 3)
    assert {:error, :query_scan_limit} = S3.query(:metrics, tenant, max_scan_rows: 3)

    assert {:error, :query_timeout} = S3.query(:metrics, tenant, deadline_ms: System.monotonic_time(:millisecond) - 1)
  end

  test "pruned and full scans agree, and language evaluation matches memory storage", %{tenant: tenant} do
    all = samples("wanted", "a") ++ samples("wanted", "b") ++ samples("other")
    assert :ok = S3.append(:metrics, tenant, samples("wanted", "a"))
    assert :ok = S3.append(:metrics, tenant, samples("wanted", "b"))
    assert :ok = S3.append(:metrics, tenant, samples("other"))
    assert {:ok, full} = S3.query(:metrics, tenant, [])
    assert {:ok, pruned} = S3.query(:metrics, tenant, matchers: [{"__name__", :eq, "wanted"}])
    assert pruned == Enum.filter(full, &(&1.labels["__name__"] == "wanted"))
    assert {:ok, entry} = ManifestOwner.ensure_loaded(tenant, "metrics", Runtime.fetch_env!(:pulse, S3))
    assert length(entry.manifest.segments) == 3
    assert length(Enum.filter(entry.manifest.segments, &(&1.metric_names == ["wanted"]))) == 2

    Memory.reset()
    :ok = Memory.append(:metrics, tenant, all, [])
    opts = %{start_ts_ns: 10_000_000_000, end_ts_ns: 20_000_000_000, step_ns: 10_000_000_000}

    for query <- [~s(wanted{job=~"api"}), "sum by(job) (rate(wanted[20s]))", "max(wanted)"] do
      Runtime.put_env(:pulse, Storage, adapter: Memory)
      assert {:ok, expected} = Evaluator.query(query, tenant, opts)
      Runtime.put_env(:pulse, Storage, adapter: S3)
      assert {:ok, ^expected} = Evaluator.query(query, tenant, opts)
    end
  end
end
