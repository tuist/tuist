defmodule Mix.Tasks.Pulse.Backfill.LokiTest do
  use PulseWeb.ConnCase, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.Pulse.Backfill.Loki
  alias Pulse.Storage

  @tag :tmp_dir
  test "prepared history replays through Loki ingest without changing nanoseconds, multiplicity or metadata", %{
    tmp_dir: dir
  } do
    # Same-nanosecond duplicates must not be collapsed, nor ns rounded through floats.
    values = [
      ["1700000000000000001", "first", %{"trace_id" => "abc", "customer" => "one"}],
      ["1700000000000000001", "second"],
      ["1700000000000000001", "second"],
      ["1700000000000000009", "last"]
    ]

    labels = %{"namespace" => "tuist", "container" => "server", "service_name" => "api"}
    source = response([%{"stream" => labels, "values" => values}])
    path = Path.join(dir, "export.json")
    File.write!(path, JSON.encode!(source) <> "\n")
    output = capture_io(fn -> Loki.run(args(path)) end)
    assert output == capture_io(fn -> Loki.run(args(path)) end)
    batch = JSON.decode!(output)
    assert batch["rows"] == 4
    assert batch["body"]["streams"] == [%{"stream" => labels, "values" => values}]
    assert batch["start_ns"] == "1700000000000000001"

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-scope-orgid", batch["tenant"])
      |> put_req_header("idempotency-key", batch["idempotency_key"])
      |> post("/loki/api/v1/push", JSON.encode!(batch["body"]))

    assert conn.status == 204
    assert get_resp_header(conn, "x-pulse-rejected-records") in [[], ["0"]]
    assert {:ok, records} = Storage.query(:logs, "archive")

    assert Enum.frequencies_by(records, &{&1.timestamp_ns, &1.body}) == %{
             {1_700_000_000_000_000_001, "first"} => 1,
             {1_700_000_000_000_000_001, "second"} => 2,
             {1_700_000_000_000_000_009, "last"} => 1
           }

    first = Enum.find(records, &(&1.body == "first"))
    assert first.resource == labels
    assert first.attributes == %{"customer" => "one"}
    assert first.trace_id == "abc"
    assert {:ok, []} = Storage.query(:logs, "other")
  end

  @tag :tmp_dir
  test "refuses capped exports, warnings, malformed entries and either side of the half-open window", %{tmp_dir: dir} do
    path = Path.join(dir, "export.json")
    stream = fn values -> [%{"stream" => %{"job" => "api"}, "values" => values}] end

    assert_raise Mix.Error, ~r/Required exactly once/, fn ->
      Loki.run(args(path) ++ ["--tenant", "other"])
    end

    for {source, overrides, error} <- [
          {response(stream.([["1700000000000000001", "x"]])), [limit: 1], ~r/reached its limit/},
          {Map.put(response([]), "warnings", ["partial"]), [], ~r/warnings/},
          {response(stream.([["1700000000000000000", "x"]])), [], ~r/outside/},
          {response(stream.([["1700000000000000010", "x"]])), [], ~r/outside/},
          {response(stream.([["1700000000000000001.0", "x"]])), [], ~r/exact decimal/},
          {response(stream.([["1700000000000000001", 12]])), [], ~r/string lines/},
          {response(stream.([["1700000000000000001", "x", %{"key" => 12}]])), [], ~r/string metadata/},
          {%{"status" => "success", "data" => %{"resultType" => "matrix", "result" => []}}, [], ~r/streams response/}
        ] do
      File.write!(path, JSON.encode!(source))
      assert_raise Mix.Error, error, fn -> Loki.run(args(path, overrides)) end
    end
  end

  @tag :tmp_dir
  test "rejects oversized inputs before JSON decoding", %{tmp_dir: dir} do
    path = Path.join(dir, "large.json")
    File.write!(path, String.duplicate(" ", 4 * 1024 * 1024 + 1))
    assert_raise Mix.Error, ~r/4 MiB/, fn -> Loki.run(args(path)) end
  end

  @tag :tmp_dir
  test "rejects duplicate JSON keys before records, warnings or metadata can be discarded", %{tmp_dir: dir} do
    path = Path.join(dir, "export.json")
    values = ~S([["1700000000000000001","history",{"customer":"one"}]])
    stream = ~s({"stream":{"job":"api"},"values":#{values}})

    for source <- [
          ~s({"status":"success","data":{"resultType":"streams","result":[],"result":[#{stream}]}}),
          ~s({"status":"success","data":{"resultType":"streams","result":[]},"warnings":[],"warnings":["partial"]}),
          ~s({"status":"success","data":{"resultType":"streams","result":[{"stream":{"job":"api"},"values":[],"values":#{values}}]}}),
          ~S({"status":"success","data":{"resultType":"streams","result":[{"stream":{"job":"api","\u006aob":"other"},"values":[["1700000000000000001","history"]]}]}}),
          ~S({"status":"success","data":{"resultType":"streams","result":[{"stream":{"job":"api"},"values":[["1700000000000000001","history",{"customer":"one","customer":"two"}]]}]}}),
          ~S({"status":"success","data":{"resultType":"streams","result":[{"stream":{"job":"api"},"values":[["1700000000000000001","history",{"customer":null,"customer":"two"}]]}]}})
        ] do
      File.write!(path, source)

      assert capture_io(fn ->
               assert_raise Mix.Error, ~r/Duplicate JSON object key/, fn -> Loki.run(args(path)) end
             end) == ""
    end

    File.write!(path, JSON.encode!(response([])) <> "{}")
    assert_raise Mix.Error, ~r/one complete JSON export/, fn -> Loki.run(args(path)) end
  end

  defp response(streams), do: %{"status" => "success", "data" => %{"resultType" => "streams", "result" => streams}}

  defp args(path, overrides \\ []) do
    [input: path, tenant: "archive", start_ns: 1_700_000_000_000_000_001, end_ns: 1_700_000_000_000_000_010, limit: 10]
    |> Keyword.merge(overrides)
    |> Enum.flat_map(fn {key, value} -> ["--" <> String.replace(to_string(key), "_", "-"), to_string(value)] end)
  end
end
