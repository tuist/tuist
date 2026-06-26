defmodule Tuist.Processor.BuildProcessorTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Processor.BuildProcessor
  alias Tuist.Processor.XCActivityLogNIF

  setup :verify_on_exit!

  defp create_build_zip(opts \\ []) do
    temp_dir =
      Path.join(
        System.tmp_dir!(),
        "build_processor_test_fixture_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(temp_dir)
    zip_path = Path.join(temp_dir, "build.zip")

    metrics_line = ~s({"timestamp":1000,"cpu":0.5})

    entries = [
      {~c"xcactivitylog/build.xcactivitylog", "log-content"},
      {~c"machine_metrics.jsonl", metrics_line}
    ]

    {:ok, _} = :zip.create(~c"#{zip_path}", entries, [{:uncompress, :all}])

    if Keyword.get(opts, :corrupt_machine_metrics, false) do
      corrupt_entry(zip_path, metrics_line)
    end

    {temp_dir, zip_path}
  end

  defp corrupt_entry(zip_path, plaintext) do
    bytes = File.read!(zip_path)
    {offset, _len} = :binary.match(bytes, plaintext)

    <<prefix::binary-size(offset), byte, rest::binary>> = bytes
    flipped = <<prefix::binary, Bitwise.bxor(byte, 0xFF), rest::binary>>

    File.write!(zip_path, flipped)
  end

  describe "process_build/2" do
    test "tolerates a corrupt machine_metrics.jsonl entry and still parses the build" do
      {fixture_dir, fixture_zip} = create_build_zip(corrupt_machine_metrics: true)
      on_exit(fn -> File.rm_rf(fixture_dir) end)

      expect(XCActivityLogNIF, :parse, fn xcactivitylog_path, _cas_db, _legacy_cas, _cache_upload ->
        assert String.ends_with?(xcactivitylog_path, ".xcactivitylog")

        {:ok,
         %{
           "time_started_recording" => 0,
           "time_stopped_recording" => 0,
           "scheme" => "App"
         }}
      end)

      assert {:ok, parsed_data} = BuildProcessor.process_build(fixture_zip, true)
      assert parsed_data["scheme"] == "App"
      assert parsed_data["machine_metrics"] == []
    end

    test "reads machine metrics when the archive is intact" do
      {fixture_dir, fixture_zip} = create_build_zip()
      on_exit(fn -> File.rm_rf(fixture_dir) end)

      expect(XCActivityLogNIF, :parse, fn _xcactivitylog_path, _cas_db, _legacy_cas, _cache_upload ->
        {:ok,
         %{
           "time_started_recording" => 1000 - 978_307_200,
           "time_stopped_recording" => 1000 - 978_307_200,
           "scheme" => "App"
         }}
      end)

      assert {:ok, parsed_data} = BuildProcessor.process_build(fixture_zip, true)
      assert [%{"timestamp" => 1000, "cpu" => 0.5}] = parsed_data["machine_metrics"]
    end
  end
end
