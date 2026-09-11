defmodule Tuist.Processor.XCActivityLogParserTest do
  # Writes a stub executable into the app's priv dir, which is global state.
  use ExUnit.Case, async: false

  alias Tuist.Processor.BuildProcessor
  alias Tuist.Processor.XCActivityLogParser

  @executable_path Path.join([:code.priv_dir(:tuist), "native", "xcactivitylog-parser"])

  defp install_parser(script) do
    File.mkdir_p!(Path.dirname(@executable_path))
    File.write!(@executable_path, "#!/bin/sh\n: > \"$5\"\n" <> script)
    File.chmod!(@executable_path, 0o755)
    on_exit(fn -> File.rm(@executable_path) end)
  end

  defp parse do
    XCActivityLogParser.parse("log.xcactivitylog", "cas.db", "cas_metadata", false, fn data ->
      {:ok, Map.update!(data, "build_steps", &Enum.to_list/1)}
    end)
  end

  test "archive samples use the activity log start, preserving fractional offsets" do
    install_parser(~S|printf '{"time_started_recording":100.125,"time_stopped_recording":102.125}' > "$4"|)
    path = Path.join(System.tmp_dir!(), "metric-offset-#{System.unique_integer([:positive])}.zip")
    on_exit(fn -> File.rm(path) end)
    samples = Enum.map_join([978_307_300.0, 978_307_300.375, 978_307_303.0], "\n", &JSON.encode!(%{timestamp: &1}))

    {:ok, _} =
      :zip.create(String.to_charlist(path), [
        {~c"xcactivitylog/build.xcactivitylog", "log"},
        {~c"machine_metrics.jsonl", samples}
      ])

    assert {:ok, [%{"offset_ms" => offset, "timestamp" => timestamp}]} =
             BuildProcessor.process_build(path, false, fn data -> {:ok, data["machine_metrics"]} end)

    assert offset == 250.0
    assert timestamp == 978_307_300.375
  end

  test "returns the decoded build data the parser wrote" do
    install_parser(~S|printf '{"status":"success","targets":[]}' > "$4"|)

    assert {:ok, %{"status" => "success", "targets" => []}} = parse()
  end

  test "returns an error when the parser is not built" do
    File.rm(@executable_path)

    assert {:error, {:parser_not_found, @executable_path}} = parse()
  end

  test "returns the parser's own message when it exits with a handled error" do
    install_parser(~S|echo "unsupported log version" >&2; exit 1|)

    assert {:error, "unsupported log version"} = parse()
  end

  test "handles repeated immediate exits after writing diagnostics" do
    install_parser(~S|echo "unsupported log version" >&2; exit 1|)

    for _ <- 1..100 do
      assert {:error, "unsupported log version"} = parse()
    end
  end

  test "captures diagnostics larger than MuonTrap's output window" do
    message = String.duplicate("unsupported log version\n", 1000)
    install_parser("printf '" <> message <> "' >&2; exit 1")

    assert {:error, String.trim(message)} == parse()
  end

  # The reason this module shells out at all: a Swift runtime trap aborts the
  # parser process, and that has to surface as an error rather than take the
  # BEAM down with it.
  test "returns a crash error when the parser dies on a signal" do
    install_parser(~S|kill -s ILL $$|)

    assert {:error, {:parser_crashed, 132, _output}} = parse()
  end

  test "leaves no output file behind" do
    install_parser(~S|printf '{"status":"success"}' > "$4"|)
    before = leftover_output_files()

    assert {:ok, _} = parse()

    assert leftover_output_files() == before
  end

  test "consumes step lines before cleaning up both files" do
    install_parser(
      ~S|printf '{"status":"success"}' > "$4"; printf '%s\n' '{"event_id":1,"log":"first"}' '{"event_id":2,"log":"last"}' > "$5"|
    )

    before = leftover_output_files()
    assert {:ok, %{"build_steps" => [%{"log" => "first"}, %{"log" => "last"}]}} = parse()
    assert leftover_output_files() == before
  end

  test "cleans up the stream when ingestion raises" do
    install_parser(~S|printf '{"status":"success"}' > "$4"; printf '%s\n' '{"event_id":1}' > "$5"|)
    before = leftover_output_files()

    assert_raise RuntimeError, "ingestion failed", fn ->
      XCActivityLogParser.parse("log", "cas", "metadata", false, fn data ->
        assert [%{"event_id" => 1}] = Enum.to_list(data["build_steps"])
        raise "ingestion failed"
      end)
    end

    assert leftover_output_files() == before
  end

  test "parse telemetry completes before consumption and excludes ingestion errors" do
    install_parser(~S|printf '{"status":"success"}' > "$4"|)
    handler = "parse-boundary-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler,
      [[:tuist, :processor, :build, :parse, :stop], [:tuist, :processor, :build, :parse, :exception]],
      fn event, _, metadata, owner -> send(owner, {event, metadata}) end,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    assert_raise RuntimeError, "ingest failed", fn ->
      XCActivityLogParser.parse("log", "cas", "metadata", false, fn _ ->
        assert_received {[:tuist, :processor, :build, :parse, :stop], %{status: :ok}}
        raise "ingest failed"
      end)
    end

    refute_received {[:tuist, :processor, :build, :parse, :exception], _}
  end

  defp leftover_output_files do
    [System.tmp_dir!(), "xcactivitylog_*.json*"] |> Path.join() |> Path.wildcard() |> Enum.sort()
  end
end
