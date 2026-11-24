defmodule Tuist.Pulse.LuftTelemetryTest do
  use ExUnit.Case, async: true

  alias Tuist.Pulse.LuftTelemetry

  @now 1_790_000_000_000_000_000
  @day 86_400 * 1_000_000_000

  defp attribute(key, value), do: %{"key" => key, "value" => %{"stringValue" => value}}

  # What Luft's core sends (`Pending::batches` in luft/crates/core/src/telemetry.rs).
  @resource %{
    "attributes" => [
      %{"key" => "service.version", "value" => %{"stringValue" => "0.4.0"}},
      %{"key" => "os.type", "value" => %{"stringValue" => "macos"}}
    ]
  }
  @scope %{"name" => "tuist-app-core", "version" => "0.4.0"}

  defp decode(signal, body) do
    {module, name} =
      case signal do
        "traces" -> {:opentelemetry_exporter_trace_service_pb, :export_trace_service_request}
        "logs" -> {:opentelemetry_exporter_logs_service_pb, :export_logs_service_request}
        "metrics" -> {:opentelemetry_exporter_metrics_service_pb, :export_metrics_service_request}
      end

    module.decode_msg(body, name)
  end

  defp spans(spans),
    do:
      {:json,
       %{"resourceSpans" => [%{"resource" => @resource, "scopeSpans" => [%{"scope" => @scope, "spans" => spans}]}]}}

  defp prepared_spans(spans) do
    {:ok, body, rejected} = LuftTelemetry.prepare("traces", spans(spans), @now)
    %{resource_spans: [%{scope_spans: [%{spans: kept}]}]} = decode("traces", body)
    {kept, rejected}
  end

  test "keeps everything Luft's core sends, including counts from a window opened days ago" do
    operation_span = %{
      "traceId" => "5b8efff798038103d269b633813fc60c",
      "spanId" => "eee19b7ec3c1b174",
      "name" => "cached_threads",
      "kind" => 1,
      "startTimeUnixNano" => Integer.to_string(@now - 1_000_000),
      "endTimeUnixNano" => Integer.to_string(@now),
      "attributes" => [attribute("luft.outcome", "error"), attribute("luft.error", "Request failed")],
      "status" => %{"code" => 2, "message" => "Request failed"}
    }

    request_span = %{
      "traceId" => "5b8efff798038103d269b633813fc60c",
      "spanId" => "aaa19b7ec3c1b174",
      "parentSpanId" => "eee19b7ec3c1b174",
      "name" => "GET /api/accounts/*/threads/*/messages",
      "kind" => 3,
      "startTimeUnixNano" => Integer.to_string(@now - 500_000),
      "endTimeUnixNano" => Integer.to_string(@now - 1000),
      "attributes" => [
        attribute("http.request.method", "GET"),
        attribute("url.path", "/api/accounts/*/threads/*/messages"),
        %{"key" => "http.response.status_code", "value" => %{"intValue" => "503"}}
      ],
      "status" => %{"code" => 2}
    }

    {kept, rejected} = prepared_spans([operation_span, request_span])
    assert rejected == 0
    assert Enum.map(kept, & &1.name) == ["cached_threads", "GET /api/accounts/*/threads/*/messages"]
    assert Enum.map(kept, &length(&1.attributes)) == [2, 3]

    logs =
      {:json,
       %{
         "resourceLogs" => [
           %{
             "resource" => @resource,
             "scopeLogs" => [
               %{
                 "scope" => @scope,
                 "logRecords" => [
                   %{
                     "timeUnixNano" => Integer.to_string(@now),
                     "severityNumber" => 9,
                     "severityText" => "INFO",
                     "body" => %{"stringValue" => "boot: ready"},
                     "traceId" => "5b8efff798038103d269b633813fc60c",
                     "spanId" => "eee19b7ec3c1b174",
                     "attributes" => [attribute("luft.operation", "boot")]
                   }
                 ]
               }
             ]
           }
         ]
       }}

    assert {:ok, body, 0} = LuftTelemetry.prepare("logs", logs, @now)
    %{resource_logs: [%{scope_logs: [%{log_records: [record]}]}]} = decode("logs", body)
    assert record.severity_number == :SEVERITY_NUMBER_INFO
    assert record.time_unix_nano == @now

    # The core's counting window opens at its last successful send, which a
    # sleeping device can leave days behind.
    window_start = @now - 8 * @day

    metrics =
      {:json,
       %{
         "resourceMetrics" => [
           %{
             "resource" => @resource,
             "scopeMetrics" => [
               %{
                 "scope" => @scope,
                 "metrics" => [
                   %{
                     "name" => "luft.core.operations",
                     "unit" => "{operation}",
                     "description" => "Operations the core ran, by outcome",
                     "sum" => %{
                       "aggregationTemporality" => 1,
                       "isMonotonic" => true,
                       "dataPoints" => [
                         %{
                           "attributes" => [
                             attribute("luft.operation", "cached_threads"),
                             attribute("luft.outcome", "ok")
                           ],
                           "startTimeUnixNano" => Integer.to_string(window_start),
                           "timeUnixNano" => Integer.to_string(@now),
                           "asInt" => "12"
                         }
                       ]
                     }
                   }
                 ]
               }
             ]
           }
         ]
       }}

    assert {:ok, body, 0} = LuftTelemetry.prepare("metrics", metrics, @now)
    %{resource_metrics: [%{scope_metrics: [%{metrics: [metric]}]}]} = decode("metrics", body)
    assert {:sum, %{data_points: [point]}} = metric.data
    assert point.value == {:as_int, 12}
    assert point.start_time_unix_nano == @now - 7 * @day
    assert [%{value: %{value: {:string_value, "cached_threads"}}}, _] = point.attributes
  end

  test "rejects records without their main time or far from now, and drops other stray times" do
    base = %{"name" => "threads", "endTimeUnixNano" => Integer.to_string(@now + 2 * @day)}
    starts = [nil, @now + 2 * @day, @now - 8 * @day, @now + 23 * 3600 * 1_000_000_000]

    {kept, rejected} =
      prepared_spans(
        for start <- starts, do: if(start, do: Map.put(base, "startTimeUnixNano", Integer.to_string(start)), else: base)
      )

    # A clock up to a day fast is kept; its out-of-window end time is dropped.
    assert rejected == 3
    assert [%{end_time_unix_nano: 0}] = kept
  end

  test "masks request names that aren't Luft's short masked paths" do
    span = fn name -> %{"name" => name, "startTimeUnixNano" => Integer.to_string(@now)} end
    long = "GET /" <> Enum.join(List.duplicate("api", 9), "/")
    eight = "GET /" <> Enum.join(List.duplicate("api", 8), "/")

    {kept, 0} = prepared_spans(Enum.map([long, eight, "TRACE /api", "GET /api/ana"], span))
    assert Enum.map(kept, & &1.name) == ["other", eight, "other", "other"]
  end

  test "turns protobuf enum numbers OTLP doesn't define into unspecified" do
    request = %{
      resource_spans: [
        %{scope_spans: [%{spans: [%{name: "threads", start_time_unix_nano: @now, kind: 99, status: %{code: 77}}]}]}
      ]
    }

    body = :opentelemetry_exporter_trace_service_pb.encode_msg(request, :export_trace_service_request)
    assert {:ok, prepared, 0} = LuftTelemetry.prepare("traces", {:protobuf, body}, @now)
    %{resource_spans: [%{scope_spans: [%{spans: [span]}]}]} = decode("traces", prepared)
    assert span.kind == :SPAN_KIND_UNSPECIFIED
    assert span.status.code == :STATUS_CODE_UNSET

    logs = %{
      resource_logs: [%{scope_logs: [%{log_records: [%{time_unix_nano: @now, severity_number: 99}]}]}]
    }

    body = :opentelemetry_exporter_logs_service_pb.encode_msg(logs, :export_logs_service_request)
    assert {:ok, prepared, 0} = LuftTelemetry.prepare("logs", {:protobuf, body}, @now)
    %{resource_logs: [%{scope_logs: [%{log_records: [record]}]}]} = decode("logs", prepared)
    assert record.severity_number == :SEVERITY_NUMBER_UNSPECIFIED
  end

  test "rejects points whose value or labels aren't Luft's, and keeps nothing else of a point" do
    labels = [attribute("luft.operation", "threads"), attribute("luft.outcome", "ok")]
    point = %{"timeUnixNano" => Integer.to_string(@now), "asInt" => "1", "attributes" => labels}

    points = [
      Map.merge(point, %{"flags" => 1, "exemplars" => [%{"asInt" => "1", "timeUnixNano" => "1"}]}),
      point |> Map.delete("asInt") |> Map.put("asDouble", 1.5),
      %{point | "asInt" => "-1"},
      %{
        point
        | "attributes" => [
            %{"key" => "luft.operation", "value" => %{"intValue" => "1"}},
            attribute("luft.outcome", "ok")
          ]
      },
      Map.delete(point, "timeUnixNano")
    ]

    metrics =
      {:json,
       %{
         "resourceMetrics" => [
           %{
             "scopeMetrics" => [
               %{
                 "metrics" => [
                   %{
                     "name" => "luft.core.operations",
                     "sum" => %{"aggregationTemporality" => 1, "isMonotonic" => true, "dataPoints" => points}
                   }
                 ]
               }
             ]
           }
         ]
       }}

    assert {:ok, body, 4} = LuftTelemetry.prepare("metrics", metrics, @now)
    %{resource_metrics: [%{scope_metrics: [%{metrics: [metric]}]}]} = decode("metrics", body)
    assert {:sum, %{data_points: [kept]}} = metric.data
    assert kept.exemplars == []
    assert kept.flags == 0
  end
end
