defmodule Processor.BuildProcessorTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Processor.BuildProcessor

  setup :verify_on_exit!

  @moduletag :tmp_dir

  describe "process/2" do
    test "downloads from S3 and processes the build", %{tmp_dir: _tmp_dir} do
      storage_key = "builds/test-build.zip"

      expect(ExAws.S3, :download_file, fn "tuist", ^storage_key, path ->
        File.write!(path, build_test_zip())
        %ExAws.Operation.S3{}
      end)

      expect(ExAws, :request, fn _ -> {:ok, :done} end)

      expect(Processor.XCActivityLogNIF, :parse, fn path, db_path, legacy_path, true ->
        assert String.ends_with?(path, "test.xcactivitylog")
        assert String.ends_with?(db_path, "cas_analytics.db")
        assert String.ends_with?(legacy_path, "cas_metadata")
        {:ok, %{"duration" => 1000, "status" => "success"}}
      end)

      assert {:ok, %{"duration" => 1000, "status" => "success"}} =
               BuildProcessor.process(storage_key, true)
    end

    test "returns error when S3 download fails", %{tmp_dir: _tmp_dir} do
      storage_key = "builds/missing.zip"

      expect(ExAws.S3, :download_file, fn "tuist", ^storage_key, _path ->
        %ExAws.Operation.S3{}
      end)

      expect(ExAws, :request, fn _ -> {:error, {:http_error, 404, "not found"}} end)

      assert {:error, {:http_error, 404, "not found"}} =
               BuildProcessor.process(storage_key, true)
    end
  end

  describe "process_build/2" do
    test "extracts build and parses xcactivitylog", %{tmp_dir: tmp_dir} do
      zip_path = write_test_zip(tmp_dir)

      expect(Processor.XCActivityLogNIF, :parse, fn path, db_path, legacy_path, true ->
        assert String.ends_with?(path, "test.xcactivitylog")
        assert String.ends_with?(db_path, "cas_analytics.db")
        assert String.ends_with?(legacy_path, "cas_metadata")
        {:ok, %{"duration" => 500, "status" => "success", "targets" => []}}
      end)

      assert {:ok, %{"duration" => 500, "status" => "success", "targets" => []}} =
               BuildProcessor.process_build(zip_path, true)
    end

    test "passes xcode_cache_upload_enabled to NIF", %{tmp_dir: tmp_dir} do
      zip_path = write_test_zip(tmp_dir)

      expect(Processor.XCActivityLogNIF, :parse, fn _path, _db_path, _legacy_path, false ->
        {:ok, %{"status" => "success"}}
      end)

      assert {:ok, _} = BuildProcessor.process_build(zip_path, false)
    end

    test "ignores manifest when present", %{tmp_dir: tmp_dir} do
      zip_path = write_test_zip(tmp_dir, manifest: %{"xcode_cache_upload_enabled" => true})

      expect(Processor.XCActivityLogNIF, :parse, fn _path, _db_path, _legacy_path, true ->
        {:ok, %{"status" => "success"}}
      end)

      assert {:ok, _} = BuildProcessor.process_build(zip_path, true)
    end

    test "includes machine metrics within time range", %{tmp_dir: tmp_dir} do
      start_time = 100.0
      end_time = 200.0

      metrics = [
        %{"timestamp" => 100 + 978_307_200, "cpu" => 50},
        %{"timestamp" => 150 + 978_307_200, "cpu" => 75},
        %{"timestamp" => 300 + 978_307_200, "cpu" => 90}
      ]

      zip_path = write_test_zip(tmp_dir, machine_metrics: metrics)

      expect(Processor.XCActivityLogNIF, :parse, fn _path, _db_path, _legacy_path, true ->
        {:ok,
         %{
           "status" => "success",
           "time_started_recording" => start_time,
           "time_stopped_recording" => end_time
         }}
      end)

      assert {:ok, result} = BuildProcessor.process_build(zip_path, true)
      assert length(result["machine_metrics"]) == 2
      assert Enum.all?(result["machine_metrics"], &(&1["cpu"] in [50, 75]))
      refute Map.has_key?(result, "time_started_recording")
      refute Map.has_key?(result, "time_stopped_recording")
    end

    test "skips malformed lines in machine_metrics.jsonl", %{tmp_dir: tmp_dir} do
      start_time = 100.0
      end_time = 200.0

      valid_metric = %{"timestamp" => 150 + 978_307_200, "cpu" => 75}

      raw_content = "{invalid json}\n#{JSON.encode!(valid_metric)}\n{\"truncated\n"

      files = [
        {~c"xcactivitylog/test.xcactivitylog", "fake log data"},
        {~c"machine_metrics.jsonl", raw_content}
      ]

      {:ok, {_, zip_bytes}} = :zip.create(~c"build.zip", files, [:memory])
      zip_path = Path.join(tmp_dir, "malformed_metrics.zip")
      File.write!(zip_path, zip_bytes)

      expect(Processor.XCActivityLogNIF, :parse, fn _path, _db_path, _legacy_path, true ->
        {:ok,
         %{
           "status" => "success",
           "time_started_recording" => start_time,
           "time_stopped_recording" => end_time
         }}
      end)

      assert {:ok, result} = BuildProcessor.process_build(zip_path, true)
      assert result["machine_metrics"] == [valid_metric]
    end
  end

  defp write_test_zip(tmp_dir, opts \\ []) do
    zip_bytes = build_test_zip(opts)
    path = Path.join(tmp_dir, "test_build_#{:erlang.unique_integer([:positive])}.zip")
    File.write!(path, zip_bytes)
    path
  end

  defp build_test_zip(opts \\ []) do
    include_xcactivitylog = Keyword.get(opts, :include_xcactivitylog, true)
    manifest = Keyword.get(opts, :manifest, nil)
    machine_metrics = Keyword.get(opts, :machine_metrics, nil)

    files =
      if include_xcactivitylog do
        [{~c"xcactivitylog/test.xcactivitylog", "fake log data"}]
      else
        [{~c"other_file.txt", "some data"}]
      end

    files =
      if manifest do
        [{~c"manifest.json", JSON.encode!(manifest)} | files]
      else
        files
      end

    files =
      if machine_metrics do
        content = machine_metrics |> Enum.map_join("\n", &JSON.encode!/1)
        [{~c"machine_metrics.jsonl", content} | files]
      else
        files
      end

    {:ok, {_filename, zip_bytes}} = :zip.create(~c"build.zip", files, [:memory])
    zip_bytes
  end
end
