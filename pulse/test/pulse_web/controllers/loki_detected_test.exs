defmodule PulseWeb.LokiDetectedTest do
  use PulseWeb.ConnCase, async: true

  alias Pulse.Record.Log
  alias Pulse.Storage

  setup %{conn: conn} do
    tenant = "detected-#{System.unique_integer([:positive])}"
    {:ok, conn: put_req_header(conn, "x-scope-orgid", tenant), tenant: tenant, now: System.system_time(:nanosecond)}
  end

  defp log(ts, body, resource, attributes \\ %{}),
    do: %Log{timestamp_ns: ts, body: body, service: "api", resource: resource, attributes: attributes}

  defp fields(conn, query, params \\ %{}) do
    conn |> get("/loki/api/v1/detected_fields", Map.put(params, "query", query)) |> json_response(200)
  end

  test "detects logfmt, JSON and structured metadata fields with types, parsers and JSON paths", ctx do
    :ok =
      Storage.append(:logs, ctx.tenant, [
        log(ctx.now - 3, "level=info duration=150ms status=200 pod=x", %{"pod" => "api-0"}, %{"trace_id" => "abc"}),
        log(ctx.now - 2, "level=warn duration=2s status=503 size=10kb", %{"pod" => "api-1"}, %{"trace_id" => "def"}),
        log(ctx.now - 1, ~s({"user":{"id":42,"tags":["a"]},"ok":true,"msg":null}), %{"pod" => "api-0"})
      ])

    response = fields(ctx.conn, ~s({service_name="api"}))
    assert response["limit"] == 1000
    by_label = Map.new(response["fields"], &{&1["label"], &1})

    assert by_label["duration"] == %{
             "label" => "duration",
             "type" => "duration",
             "cardinality" => 2,
             "parsers" => ["logfmt"]
           }

    assert by_label["status"]["type"] == "int"
    assert by_label["size"]["type"] == "bytes"
    assert by_label["pod_extracted"]["parsers"] == ["logfmt"]
    assert by_label["trace_id"] == %{"label" => "trace_id", "type" => "string", "cardinality" => 2, "parsers" => nil}

    assert by_label["user_id"] == %{
             "label" => "user_id",
             "type" => "int",
             "cardinality" => 1,
             "parsers" => ["json"],
             "jsonPath" => ["user", "id"]
           }

    assert by_label["ok"]["type"] == "boolean"
    refute Map.has_key?(by_label, "msg")
    refute Map.has_key?(by_label, "user_tags")
    refute Map.has_key?(by_label, "pod")
  end

  test "samples only the newest line_limit lines and caps the field count", ctx do
    :ok =
      Storage.append(:logs, ctx.tenant, [
        log(ctx.now - 2, "old=1", %{}),
        log(ctx.now - 1, "new=1 other=2", %{})
      ])

    labels = fn response -> Enum.map(response["fields"], & &1["label"]) end
    assert labels.(fields(ctx.conn, ~s({service_name="api"}), %{"line_limit" => "1"})) == ["new", "other"]
    assert [_one] = fields(ctx.conn, ~s({service_name="api"}), %{"limit" => "1"})["fields"]
    assert fields(ctx.conn, ~s({service_name="none"})) == %{}
  end

  test "includes labels extracted by the query's own parsers", ctx do
    :ok = Storage.append(:logs, ctx.tenant, [log(ctx.now - 1, "GET /api 200", %{})])

    response = fields(ctx.conn, ~S[{service_name="api"} | regexp "(?P<method>\\w+) (?P<path>\\S+)"])
    by_label = Map.new(response["fields"], &{&1["label"], &1})
    assert by_label["method"]["parsers"] == ["logfmt"]
    assert by_label["path"]["type"] == "string"
  end

  test "returns detected field values, normalizing byte sizes", ctx do
    :ok =
      Storage.append(:logs, ctx.tenant, [
        log(ctx.now - 2, "size=1500kb route=/a", %{}),
        log(ctx.now - 1, "size=2kb route=/b", %{})
      ])

    values = fn name ->
      ctx.conn
      |> get("/loki/api/v1/detected_field/#{name}/values", %{"query" => ~s({service_name="api"})})
      |> json_response(200)
    end

    assert values.("route") == %{"values" => ["/a", "/b"], "limit" => 1000}
    assert values.("size") == %{"values" => ["1.5MB", "2.0kB"], "limit" => 1000}
    assert values.("missing") == %{}
  end

  test "detects stream labels, omitting all-numeric and UUID labels except static ones", ctx do
    :ok =
      Storage.append(:logs, ctx.tenant, [
        log(ctx.now - 2, "a", %{
          "app" => "web",
          "pod" => "1",
          "request" => "1",
          "id" => "0b8f6d1e-6c0e-4a43-9a43-1c3a0c1a2b3c"
        }),
        log(ctx.now - 1, "b", %{
          "app" => "api",
          "pod" => "2",
          "request" => "2",
          "id" => "1b8f6d1e-6c0e-4a43-9a43-1c3a0c1a2b3c"
        })
      ])

    response = ctx.conn |> get("/loki/api/v1/detected_labels", %{"query" => ~s({app=~".+"})}) |> json_response(200)

    assert response == %{
             "detectedLabels" => [
               %{"label" => "app", "cardinality" => 2},
               %{"label" => "pod", "cardinality" => 2},
               %{"label" => "service_name", "cardinality" => 1}
             ]
           }
  end

  test "rejects metric queries and invalid limits", ctx do
    assert ctx.conn
           |> get("/loki/api/v1/detected_fields", %{"query" => ~s<count_over_time({service_name="api"}[1m])>})
           |> json_response(400)

    assert ctx.conn
           |> get("/loki/api/v1/detected_fields", %{"query" => ~s({service_name="api"}), "line_limit" => "0"})
           |> json_response(400)
  end
end
