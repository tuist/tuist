defmodule Pulse.Reliability.WindowsTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Loki.Push
  alias Pulse.OTLP.{Logs, Metrics, Traces}
  alias Pulse.Record.{Log, MetricSample, Span}
  alias Pulse.Reliability.Windows
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.Memory
  alias Pulse.Test.OTLPLogFixture
  alias Pulse.Test.OTLPMetricFixture
  alias Pulse.Test.OTLPTraceFixture

  @minute 60_000_000_000
  @finish 100 * @minute

  setup do
    Runtime.put_env(:pulse, Storage, adapter: __MODULE__)
    :ok
  end

  # A test-owned recording boundary delegates real reads/writes to the owned
  # Memory adapter. Faults affect only this test's dependency context.
  def append(signal, tenant, rows, opts), do: Memory.append(signal, tenant, rows, opts)

  def query(signal, tenant, opts) do
    send(self(), {:query, signal, opts})

    case Runtime.get_env(:pulse, :windows_fault) do
      {^signal, result} -> result
      _ -> Memory.query(signal, tenant, opts)
    end
  end

  test "exact asymmetric half-open boundaries, ordinary logs, all kinds joint once" do
    times = [
      65 * @minute - 1,
      65 * @minute,
      66 * @minute,
      95 * @minute - 1,
      95 * @minute,
      99 * @minute,
      @finish - 1,
      @finish
    ]

    :ok = Storage.append(:logs, "tenant", Enum.map(times, &log/1))
    :ok = Storage.append(:metrics, "tenant", Enum.map(times, &metric(&1, "temperature", 7)))
    :ok = Storage.append(:traces, "tenant", Enum.map(times, &span(&1, 2_000_000)))
    deadline = deadline()
    assert {:ok, snapshot} = Windows.scan("tenant", nil, @finish, deadline)
    [group] = Map.values(snapshot["groups"])

    for kind <- ~w(logs metrics traces) do
      assert group["baseline"][kind]["count"] == 3
      assert group["current"][kind]["count"] == 3
    end

    assert group["current"]["logs"]["errors"] == 0
    assert group["baseline"]["start_ns"] == 65 * @minute
    assert group["baseline"]["finish_ns"] == 95 * @minute
    assert group["current"]["finish_ns"] == @finish
    assert snapshot == snapshot |> Pulse.JSON.encode!() |> Pulse.JSON.decode!()

    for kind <- [:logs, :metrics, :traces] do
      assert_receive {:query, ^kind, opts}
      assert opts[:start_ts] == 65 * @minute
      assert opts[:end_ts] == @finish - 1
      assert opts[:fresh] == true
      assert opts[:distinguish_missing_authority] == true
      assert opts[:deadline_ms] == deadline
      assert opts[:max_records] == 10_000
      assert opts[:max_decoded_bytes] == 8 * 1024 * 1024
      assert opts[:max_scan_segments] == 128
      assert opts[:max_scan_bytes] == 16 * 1024 * 1024
      assert opts[:max_scan_rows] == 100_000
      refute Keyword.has_key?(opts, :limit)
    end

    refute_receive {:query, _, _}
    assert {:ok, evidence} = Windows.query(group, "slow_traces")
    assert evidence["current"]["duration_ns"]["min"] == 2_000_000
    assert {:error, :unknown_query} = Windows.query(group, "SELECT * FROM secrets")
    input = Windows.input(group)
    refute Map.has_key?(input, "queries")

    for window <- ~w(baseline current) do
      refute Map.has_key?(input[window]["logs"], "patterns")
      refute Map.has_key?(input[window]["metrics"], "names")
      refute Map.has_key?(input[window]["traces"], "histogram")
      refute Map.has_key?(input[window]["traces"], "histogram_upper_exclusive_ns")
    end

    refute_receive {:query, _, _}
    refute Pulse.JSON.encode!(snapshot) =~ "super-secret"
  end

  test "repair replaces overlap, accepts late data, reuses old bins and expires known groups as missing" do
    :ok = Storage.append(:logs, "tenant", Enum.map([70, 92, 98], &log(&1 * @minute)))
    assert {:ok, before} = Windows.scan("tenant", nil, @finish, deadline())
    :ok = Storage.append(:logs, "tenant", [log(93 * @minute), log(103 * @minute)])
    assert {:ok, after_scan} = Windows.scan("tenant", before, 105 * @minute, deadline())
    [group] = Map.values(after_scan["groups"])
    assert group["baseline"]["logs"]["count"] == 4
    assert group["current"]["logs"]["count"] == 1
    assert after_scan["coverage"]["repair_start_ns"] == 90 * @minute
    assert after_scan["bins"][Integer.to_string(70 * @minute)] == before["bins"][Integer.to_string(70 * @minute)]
    assert {:ok, again} = Windows.scan("tenant", after_scan, 105 * @minute, deadline())
    assert again["groups"] == after_scan["groups"]
    assert {:ok, expired} = Windows.scan("tenant", again, 150 * @minute, deadline())
    [empty] = Map.values(expired["groups"])
    assert empty["current"]["logs"]["count"] == 0
    assert empty["baseline"]["logs"]["count"] == 0
    assert empty["current"]["coverage"] =~ "missing"
    assert expired["bins"] == %{}
  end

  test "non-minute phase keeps exact windows and phase changes safely rescan" do
    finish = @finish + 17

    :ok =
      Storage.append(
        :logs,
        "tenant",
        Enum.map(
          [
            finish - 35 * @minute - 1,
            finish - 35 * @minute,
            finish - 5 * @minute - 1,
            finish - 5 * @minute,
            finish - 1,
            finish
          ],
          &log/1
        )
      )

    assert {:ok, snapshot} = Windows.scan("tenant", nil, finish, deadline())
    [group] = Map.values(snapshot["groups"])
    assert group["baseline"]["logs"]["count"] == 2
    assert group["current"]["logs"]["count"] == 2
    assert {:ok, next} = Windows.scan("tenant", snapshot, finish + 1, deadline())
    assert next["coverage"]["repair_start_ns"] == finish + 1 - 35 * @minute
  end

  test "service/environment separation joins all modalities and unknown is explicit" do
    :ok =
      Storage.append(:logs, "tenant", [
        log(99 * @minute),
        %{log(99 * @minute) | resource: %{"deployment.environment.name" => "staging"}},
        %{log(99 * @minute) | service: nil, resource: %{}}
      ])

    :ok = Storage.append(:metrics, "tenant", [metric(99 * @minute, "temperature", 4)])
    :ok = Storage.append(:traces, "tenant", [span(99 * @minute, 20)])
    assert {:ok, snapshot} = Windows.scan("tenant", nil, @finish, deadline())
    groups = Map.values(snapshot["groups"])
    assert length(groups) == 3
    prod = Enum.find(groups, &(&1["environment"] == "prod"))
    assert prod["service"] == "api"
    assert prod["current"]["logs"]["count"] == 1
    assert prod["current"]["metrics"]["count"] == 1
    assert prod["current"]["traces"]["count"] == 1
    assert Enum.any?(groups, &(&1["service"] == "unknown" and &1["environment"] == "unknown"))
  end

  test "original OTLP resource strings join signals despite namespaced metric jobs and separate environments" do
    for environment <- ["prod", "staging"], namespace <- ["shop", "other"] do
      resource = resource("api", environment, namespace)
      [sample] = otlp_metrics(resource)
      assert sample.labels["job"] == "#{namespace}/api"
      refute Map.has_key?(sample.labels, "deployment_environment_name")
      :ok = Storage.append(:metrics, "tenant", [sample])
      :ok = Storage.append(:logs, "tenant", otlp_logs(resource, [%{"severityText" => "INFO"}]))
      :ok = Storage.append(:traces, "tenant", otlp_traces(resource))
    end

    assert {:ok, snapshot} = Windows.scan("tenant", nil, @finish, deadline())
    groups = Map.values(snapshot["groups"])
    assert length(groups) == 2

    for environment <- ["prod", "staging"] do
      group = Enum.find(groups, &(&1["environment"] == environment))
      assert group["service"] == "api"

      for signal <- ~w(logs metrics traces) do
        assert group["current"][signal]["count"] == 2
      end
    end
  end

  test "canonical OTLP identity wins over conflicting custom aliases across signals" do
    attributes =
      resource("api", "prod", "shop")["attributes"] ++
        identity_aliases() ++
        [%{"key" => "deployment.environment", "value" => %{"stringValue" => "old-prod"}}]

    assert_resource_identity(attributes, "api", "prod")
    assert_resource_identity(Enum.reverse(attributes), "api", "prod")
  end

  test "missing OTLP canonical dimensions do not infer custom aliases across signals" do
    assert_resource_identity(identity_aliases(), "unknown", "unknown")
    assert_resource_identity([], "unknown", "unknown")

    attributes = [
      %{"key" => "service.name", "value" => %{"stringValue" => "api"}},
      %{"key" => "deployment.environment", "value" => %{"stringValue" => "old-prod"}}
      | identity_aliases()
    ]

    assert_resource_identity(attributes, "api", "old-prod")
  end

  test "nonstring and empty canonical OTLP dimensions cannot be rescued by aliases" do
    for value <- [%{"bytesValue" => Base.encode64("api")}, %{"doubleValue" => "NaN"}, %{"stringValue" => ""}] do
      attributes = [
        %{"key" => "service.name", "value" => value},
        %{"key" => "deployment.environment.name", "value" => value},
        %{"key" => "deployment.environment", "value" => %{"stringValue" => "old-prod"}}
        | identity_aliases()
      ]

      assert_resource_identity(attributes, "unknown", "unknown")
    end

    for value <- [%{"intValue" => "42"}, %{"boolValue" => true}] do
      attributes = [
        %{"key" => "service.name", "value" => %{"stringValue" => "api"}},
        %{"key" => "deployment.environment.name", "value" => value},
        %{"key" => "deployment.environment", "value" => %{"stringValue" => "old-prod"}}
        | identity_aliases()
      ]

      assert_resource_identity(attributes, "api", "unknown")
    end
  end

  test "typed nonstring resource values never become identity strings" do
    for value <- [
          %{"bytesValue" => Base.encode64("api")},
          %{"intValue" => "42"},
          %{"boolValue" => true},
          %{"doubleValue" => "NaN"}
        ] do
      resource = %{
        "attributes" => [
          %{"key" => "service.name", "value" => value},
          %{"key" => "deployment.environment.name", "value" => value}
        ]
      }

      # Numeric/bool service names fail metric projection admission already;
      # bytes and nonfinite doubles project strings but are not stringValue.
      if Map.has_key?(value, "bytesValue") or Map.has_key?(value, "doubleValue") do
        :ok = Storage.append(:metrics, "tenant", otlp_metrics(resource))
      end

      :ok = Storage.append(:logs, "tenant", otlp_logs(resource, [%{"severityText" => "INFO"}]))
      :ok = Storage.append(:traces, "tenant", otlp_traces(resource))
    end

    assert {:ok, snapshot} = Windows.scan("tenant", nil, @finish, deadline())
    [group] = Map.values(snapshot["groups"])
    assert group["service"] == "unknown"
    assert group["environment"] == "unknown"

    assert group["current"]["metrics"]["count"] == 2

    for signal <- ~w(logs traces) do
      assert group["current"][signal]["count"] == 4
    end
  end

  test "legacy and remote-write identity labels remain fallbacks without typed resources" do
    :ok = Storage.append(:logs, "tenant", [log(99 * @minute)])
    :ok = Storage.append(:traces, "tenant", [span(99 * @minute, 1)])

    samples = [
      metric(99 * @minute, "temperature", 1),
      %MetricSample{
        timestamp_ns: 99 * @minute,
        value: 2,
        labels: %{"__name__" => "remote", "job" => "api", "environment" => "prod"}
      },
      %MetricSample{timestamp_ns: 99 * @minute, value: 3, labels: %{"__name__" => "unidentified"}}
    ]

    :ok = Storage.append(:metrics, "tenant", samples)
    assert {:ok, snapshot} = Windows.scan("tenant", nil, @finish, deadline())
    groups = Map.values(snapshot["groups"])
    assert length(groups) == 2
    prod = Enum.find(groups, &(&1["environment"] == "prod"))
    assert prod["service"] == "api"
    assert prod["current"]["metrics"]["count"] == 2
    assert prod["current"]["logs"]["count"] == 1
    assert prod["current"]["traces"]["count"] == 1
    unknown = Enum.find(groups, &(&1["service"] == "unknown"))
    assert unknown["environment"] == "unknown"
    assert unknown["current"]["metrics"]["count"] == 1
  end

  test "long valid severity text cannot reject a window and numeric errors remain authoritative" do
    custom = "ERROR" <> String.duplicate("界", 4096)

    rows =
      otlp_logs(resource("api", "prod", "shop"), [
        %{"severityText" => custom, "severityNumber" => 17},
        %{"severityText" => custom},
        %{"severityText" => "critical"},
        %{"severityText" => "error", "severityNumber" => 9}
      ])

    assert Enum.take(Enum.map(rows, & &1.severity_text), 2) == [custom, custom]
    :ok = Storage.append(:logs, "tenant", rows)

    assert {[loki], 0} =
             Push.decode(%{
               "streams" => [
                 %{
                   "stream" => %{"service_name" => "api", "environment" => "prod", "level" => custom},
                   "values" => [[Integer.to_string(99 * @minute), "custom severity"]]
                 }
               ]
             })

    assert loki.severity_text == custom
    assert loki.severity_number == nil
    :ok = Storage.append(:logs, "tenant", [loki, %{log(99 * @minute) | severity_text: custom, severity_number: 17}])

    assert {:ok, snapshot} = Windows.scan("tenant", nil, @finish, deadline())
    [group] = Map.values(snapshot["groups"])
    assert group["current"]["logs"]["count"] == 6
    assert group["current"]["logs"]["errors"] == 4
    refute Pulse.JSON.encode!(snapshot) =~ custom
  end

  test "finite scalar inventory excludes unknown/nonfinite/histogram samples, caps names, preserves last not mean" do
    samples =
      [metric(98 * @minute, "temperature", 4), metric(99 * @minute, "temperature", 10)] ++
        Enum.map([:nan, :infinity, :negative_infinity, :stale, :unknown, nil], &metric(99 * @minute, "temperature", &1)) ++
        [%{metric(99 * @minute, "temperature", nil) | histogram: %{}}] ++
        Enum.map(1..12, &metric(99 * @minute, "extra_#{&1}", &1))

    :ok = Storage.append(:metrics, "tenant", samples)

    :ok =
      Storage.append(:traces, "tenant", [
        span(99 * @minute, 1),
        span(98 * @minute, 10_000_000_000),
        %{span(99 * @minute, 5) | kind: 1}
      ])

    assert {:ok, snapshot} = Windows.scan("tenant", nil, @finish, deadline())
    [group] = Map.values(snapshot["groups"])
    metrics = group["current"]["metrics"]
    assert map_size(metrics["names"]) <= 8
    assert metrics["excluded_samples"] >= 7

    assert Enum.sum(Enum.map(metrics["names"], fn {_, stats} -> stats["count"] end)) + metrics["excluded_samples"] ==
             metrics["count"]

    traces = group["current"]["traces"]
    assert traces["count"] == 2
    assert traces["excluded_spans"] == 1
    assert traces["duration_ns"]["min"] == 1
    assert traces["duration_ns"]["max"] == 10_000_000_000
    assert Enum.sum(traces["histogram"]) == 2
    refute Pulse.JSON.encode!(snapshot) =~ "private-label"

    :ok =
      Storage.append(:metrics, "simple", [
        metric(98 * @minute, "temperature", 4),
        metric(99 * @minute, "temperature", 10)
      ])

    assert {:ok, simple} = Windows.scan("simple", nil, @finish, deadline())
    [group] = Map.values(simple["groups"])

    assert group["current"]["metrics"]["names"]["temperature"] ==
             %{"count" => 2, "min" => 4, "max" => 10, "last" => 10, "last_ns" => 99 * @minute}
  end

  test "group and identity limits fail whole, never silent top-k" do
    :ok = Storage.append(:logs, "tenant", Enum.map(1..101, &%{log(99 * @minute) | service: "service_#{&1}"}))
    assert {:error, :reliability_group_limit} = Windows.scan("tenant", nil, @finish, deadline())
    :ok = Storage.append(:logs, "long", [%{log(99 * @minute) | service: String.duplicate("a", 129)}])
    assert {:error, :reliability_identity_limit} = Windows.scan("long", nil, @finish, deadline())
  end

  test "metric name cap is shared across windows, severity/status errors retain ordinary observations" do
    :ok =
      Storage.append(
        :metrics,
        "tenant",
        Enum.map(1..8, &metric(70 * @minute, "baseline_#{&1}", &1)) ++
          Enum.map(1..8, &metric(99 * @minute, "current_#{&1}", &1))
      )

    :ok =
      Storage.append(:logs, "tenant", [
        log(99 * @minute),
        %{log(99 * @minute) | severity_number: 17},
        %{log(99 * @minute) | severity_text: "error"}
      ])

    :ok = Storage.append(:traces, "tenant", [%{span(99 * @minute, 100) | status: %{"code" => 2}}])
    assert {:ok, snapshot} = Windows.scan("tenant", nil, @finish, deadline())
    [group] = Map.values(snapshot["groups"])
    names = Map.keys(group["baseline"]["metrics"]["names"]) ++ Map.keys(group["current"]["metrics"]["names"])
    assert length(Enum.uniq(names)) == 8
    assert group["current"]["metrics"]["excluded_samples"] == 8
    assert group["current"]["logs"]["count"] == 3
    assert group["current"]["logs"]["errors"] == 2
    assert group["current"]["traces"]["errors"] == 1
    assert {:ok, evidence} = Windows.query(group, "log_patterns")
    assert evidence["current"]["count"] == 3
  end

  test "serialized snapshot cap fails whole even when each signal fits its row ceiling" do
    samples =
      for service <- 1..100, minute <- 65..97, name <- 1..3 do
        sample = metric(minute * @minute, String.duplicate("n", 120) <> "_#{name}", 1.797_693_134_862_315_7e308)
        %{sample | labels: Map.put(sample.labels, "service_name", "service_#{service}")}
      end

    :ok = Storage.append(:metrics, "tenant", samples)

    logs =
      for service <- 1..100, minute <- 65..97, shape <- 1..3 do
        %{log(minute * @minute) | service: "service_#{service}", body: String.duplicate("redacted", shape)}
      end

    :ok = Storage.append(:logs, "tenant", logs)
    assert {:error, :reliability_snapshot_limit} = Windows.scan("tenant", nil, @finish, deadline())
  end

  test "only explicitly missing signal authority is treated as absent observations" do
    :ok = Storage.append(:logs, "tenant", [log(99 * @minute)])
    Runtime.put_env(:pulse, :windows_fault, {:metrics, {:error, :signal_authority_missing}})
    assert {:ok, snapshot} = Windows.scan("tenant", nil, @finish, deadline())
    [group] = Map.values(snapshot["groups"])
    assert group["current"]["logs"]["count"] == 1
    assert group["current"]["metrics"]["count"] == 0
    assert group["current"]["coverage"] =~ "missing_is_unknown"
    Runtime.put_env(:pulse, :windows_fault, {:metrics, {:error, :not_found}})
    assert {:error, :not_found} = Windows.scan("tenant", nil, @finish, deadline())
  end

  test "row ceilings and storage failures cannot publish partially healthy evidence" do
    :ok = Storage.append(:logs, "tenant", [log(99 * @minute)])
    Runtime.put_env(:pulse, :windows_fault, {:metrics, {:error, :storage_unavailable}})
    assert {:error, :storage_unavailable} = Windows.scan("tenant", nil, @finish, deadline())
    Runtime.put_env(:pulse, :windows_fault, {:traces, {:error, :not_found}})
    assert {:error, :not_found} = Windows.scan("tenant", nil, @finish, deadline())
    Runtime.put_env(:pulse, :windows_fault, {:logs, {:ok, List.duplicate(log(99 * @minute), 10_001)}})
    assert {:error, :reliability_row_limit} = Windows.scan("tenant", nil, @finish, deadline())
    assert {:error, :query_timeout} = Windows.scan("tenant", nil, @finish, System.monotonic_time(:millisecond))
  end

  test "wrong signal types and invalid source/end/observed times reject before aggregation" do
    for row <- [
          metric(99 * @minute, "temperature", 4),
          %{log(99 * @minute) | timestamp_ns: nil},
          %{log(99 * @minute) | timestamp_ns: @finish},
          %{log(99 * @minute) | observed_timestamp_ns: -1}
        ] do
      Runtime.put_env(:pulse, :windows_fault, {:logs, {:ok, [row]}})
      assert {:error, reason} = Windows.scan("tenant", nil, @finish, deadline())
      assert reason in [:reliability_invalid_time, :reliability_invalid_row]
    end

    Runtime.put_env(:pulse, :windows_fault, {:traces, {:ok, [%{span(99 * @minute, 1) | end_timestamp_ns: 0}]}})
    assert {:error, :reliability_invalid_time} = Windows.scan("tenant", nil, @finish, deadline())
  end

  defp deadline, do: System.monotonic_time(:millisecond) + 30_000

  defp identity_aliases do
    Enum.map(
      ~w(service_name service job deployment_environment deployment_environment_name environment env),
      &%{"key" => &1, "value" => %{"stringValue" => "other"}}
    )
  end

  defp assert_resource_identity(attributes, service, environment) do
    tenant = "identity-#{System.unique_integer([:positive])}"
    resource = %{"attributes" => attributes}
    :ok = Storage.append(:metrics, tenant, otlp_metrics(resource))
    :ok = Storage.append(:logs, tenant, otlp_logs(resource, [%{"severityText" => "INFO"}]))
    :ok = Storage.append(:traces, tenant, otlp_traces(resource))
    assert {:ok, snapshot} = Windows.scan(tenant, nil, @finish, deadline())
    [group] = Map.values(snapshot["groups"])
    assert group["service"] == service
    assert group["environment"] == environment

    for signal <- ~w(logs metrics traces) do
      assert group["current"][signal]["count"] == 1
    end
  end

  defp resource(service, environment, namespace) do
    %{
      "attributes" =>
        Enum.map(
          [{"service.name", service}, {"deployment.environment.name", environment}, {"service.namespace", namespace}],
          fn {key, value} -> %{"key" => key, "value" => %{"stringValue" => value}} end
        )
    }
  end

  defp otlp_metrics(resource) do
    payload = %{
      "resourceMetrics" => [
        %{
          "resource" => resource,
          "scopeMetrics" => [
            %{
              "metrics" => [
                %{
                  "name" => "temperature",
                  "gauge" => %{"dataPoints" => [%{"timeUnixNano" => Integer.to_string(99 * @minute), "asInt" => "7"}]}
                }
              ]
            }
          ]
        }
      ]
    }

    assert {:ok, rows, 0} = Metrics.decode(payload)
    assert Metrics.decode_protobuf(OTLPMetricFixture.protobuf(payload)) == {:ok, rows, 0}
    rows
  end

  defp otlp_logs(resource, records) do
    records = Enum.map(records, &Map.put(&1, "timeUnixNano", Integer.to_string(99 * @minute)))
    payload = %{"resourceLogs" => [%{"resource" => resource, "scopeLogs" => [%{"logRecords" => records}]}]}
    assert {:ok, rows, 0} = Logs.decode(payload)
    assert Logs.decode_protobuf(OTLPLogFixture.protobuf(payload)) == {:ok, rows, 0}
    rows
  end

  defp otlp_traces(resource) do
    payload = %{
      "resourceSpans" => [
        %{"resource" => resource, "scopeSpans" => [%{"spans" => [OTLPTraceFixture.span(99 * @minute)]}]}
      ]
    }

    assert {:ok, rows, 0} = Traces.decode(payload)
    assert Traces.decode_protobuf(OTLPTraceFixture.protobuf(payload)) == {:ok, rows, 0}
    rows
  end

  defp log(ts),
    do: %Log{
      timestamp_ns: ts,
      severity_text: "INFO",
      service: "api",
      body: "super-secret token=123",
      resource: %{"deployment.environment.name" => "prod"}
    }

  defp metric(ts, name, value),
    do: %MetricSample{
      timestamp_ns: ts,
      value: value,
      labels: %{
        "__name__" => name,
        "service_name" => "api",
        "deployment_environment" => "prod",
        "token" => "private-label"
      }
    }

  defp span(ts, duration),
    do: %Span{
      timestamp_ns: ts,
      end_timestamp_ns: ts + duration,
      kind: 2,
      service: "api",
      resource: %{"deployment.environment.name" => "prod"}
    }
end
