defmodule Tuist.Processor.BuildProcessor do
  @moduledoc """
  Parses xcactivitylog build archives.

  The server's `ProcessBuildWorker` Oban job is the only caller: it downloads
  the archive from S3 into a temp file, hands the path to `process_build/2`,
  writes the returned structured data to the DB, and deletes the temp file.

  On processor-mode pods (`TUIST_PROCESSOR_MODE=true`) this runs as the Oban
  worker body — the CPU-heavy parse work is scheduled onto dedicated replicas
  rather than every web server pod. On self-hosted installs it runs in the
  same BEAM as the rest of the server.
  """

  @apple_reference_date_offset 978_307_200

  def process_build(build_zip_path, xcode_cache_upload_enabled) do
    temp_dir = make_temp_dir()

    try do
      :telemetry.span([:tuist, :processor, :build], %{}, fn ->
        result = process_zip(build_zip_path, temp_dir, xcode_cache_upload_enabled)
        status = if match?({:ok, _}, result), do: :ok, else: :error
        {result, %{status: status}}
      end)
    after
      cleanup_temp(temp_dir)
    end
  end

  defp process_zip(zip_path, temp_dir, xcode_cache_upload_enabled) do
    {:ok, _} = :zip.unzip(~c"#{zip_path}", [{:cwd, ~c"#{temp_dir}"}])
    xcactivitylog_path = find_xcactivitylog(temp_dir)
    cas_analytics_db_path = Path.join(temp_dir, "cas_analytics.db")
    legacy_cas_metadata_path = Path.join(temp_dir, "cas_metadata")

    with {:ok, parsed_data} <-
           parse_build(
             xcactivitylog_path,
             cas_analytics_db_path,
             legacy_cas_metadata_path,
             xcode_cache_upload_enabled
           ) do
      machine_metrics =
        read_machine_metrics(
          Path.join(temp_dir, "machine_metrics.jsonl"),
          parsed_data["time_started_recording"],
          parsed_data["time_stopped_recording"]
        )

      parsed_data =
        parsed_data
        |> Map.drop(["time_started_recording", "time_stopped_recording"])
        |> Map.put("machine_metrics", machine_metrics)

      {:ok, parsed_data}
    end
  end

  defp parse_build(xcactivitylog_path, cas_analytics_db_path, legacy_cas_metadata_path, xcode_cache_upload_enabled) do
    :telemetry.span([:tuist, :processor, :build, :parse], %{}, fn ->
      result =
        Tuist.Processor.XCActivityLogNIF.parse(
          xcactivitylog_path,
          cas_analytics_db_path,
          legacy_cas_metadata_path,
          xcode_cache_upload_enabled
        )

      status = if match?({:ok, _}, result), do: :ok, else: :error
      {result, %{status: status}}
    end)
  end

  defp make_temp_dir do
    temp_dir = Path.join(System.tmp_dir!(), "tuist_processor_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(temp_dir)
    temp_dir
  end

  defp find_xcactivitylog(temp_dir) do
    xcactivitylog_dir = Path.join(temp_dir, "xcactivitylog")

    {:ok, files} = File.ls(xcactivitylog_dir)
    file = Enum.find(files, &String.ends_with?(&1, ".xcactivitylog"))
    Path.join(xcactivitylog_dir, file)
  end

  defp read_machine_metrics(path, start_time, end_time) do
    if File.exists?(path) do
      start_unix = start_time + @apple_reference_date_offset
      end_unix = end_time + @apple_reference_date_offset

      path
      |> File.stream!()
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Stream.map(fn line -> JSON.decode(line) end)
      |> Stream.filter(&match?({:ok, _}, &1))
      |> Stream.map(fn {:ok, decoded} -> decoded end)
      |> Stream.filter(fn sample ->
        ts = sample["timestamp"]
        ts >= start_unix and ts <= end_unix
      end)
      |> Enum.to_list()
    else
      []
    end
  end

  defp cleanup_temp(temp_dir) do
    File.rm_rf(temp_dir)
    :ok
  end
end
