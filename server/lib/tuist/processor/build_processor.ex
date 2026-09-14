defmodule Tuist.Processor.BuildProcessor do
  @moduledoc """
  Parses xcactivitylog build archives.

  The server's `ProcessBuildWorker` Oban job is the only caller: it downloads
  the archive from S3 into a temp file, hands the path to `process_build/3`,
  consumes structured data through a callback while temporary files exist, and
  deletes the archive afterward. Step logs stream from a JSONL sidecar.

  On processor-mode pods (`TUIST_MODE=processor`) this runs as the Oban
  worker body — the CPU-heavy parse work is scheduled onto dedicated replicas
  rather than every web server pod. On self-hosted installs it runs in the
  same BEAM as the rest of the server.
  """

  alias Tuist.Processor.XCActivityLogParser

  @apple_reference_date_offset 978_307_200

  # Reasons `:zip.unzip/2` returns when the archive itself is malformed. The
  # download layer guarantees the object was fully written before we open it,
  # so these are customer-side bad uploads (truncated by the client, wrong
  # bytes, or already corrupt on their disk) rather than a transport problem.
  # Callers surface them as `{:error, :corrupt_archive}` and skip retrying.
  @corrupt_archive_zip_reasons ~w(
    bad_eocd
    eocd_not_found
    file_header_not_found
    bad_local_file_header
    invalid_zip_file
    bad_central_directory
    bad_zip_file
  )a

  def process_build(build_zip_path, xcode_cache_upload_enabled, consume) do
    temp_dir = make_temp_dir()

    try do
      :telemetry.span([:tuist, :processor, :build], %{}, fn ->
        result = process_zip(build_zip_path, temp_dir, xcode_cache_upload_enabled, consume)
        status = if match?({:ok, _}, result), do: :ok, else: :error
        {result, %{status: status}}
      end)
    after
      cleanup_temp(temp_dir)
    end
  end

  defp process_zip(zip_path, temp_dir, xcode_cache_upload_enabled, consume) do
    case :zip.unzip(~c"#{zip_path}", [{:cwd, ~c"#{temp_dir}"}]) do
      {:ok, _} ->
        process_extracted_build(temp_dir, xcode_cache_upload_enabled, consume)

      {:error, reason} when reason in @corrupt_archive_zip_reasons ->
        {:error, :corrupt_archive}

      # `:zip.unzip` reports a per-entry failure as `{FileName, Reason}`, most
      # commonly `:bad_crc` when the archive's entry bytes don't match its
      # recorded checksum. Same class of problem as a bad EOCD: the customer's
      # upload is corrupt and retries won't heal it.
      {:error, {_file, reason}} when reason in @corrupt_archive_zip_reasons ->
        {:error, :corrupt_archive}

      {:error, {_file, :bad_crc}} ->
        {:error, :corrupt_archive}

      {:error, _} = error ->
        error
    end
  end

  defp process_extracted_build(temp_dir, xcode_cache_upload_enabled, consume) do
    xcactivitylog_path = find_xcactivitylog(temp_dir)
    cas_analytics_db_path = Path.join(temp_dir, "cas_analytics.db")
    legacy_cas_metadata_path = Path.join(temp_dir, "cas_metadata")

    XCActivityLogParser.parse(
      xcactivitylog_path,
      cas_analytics_db_path,
      legacy_cas_metadata_path,
      xcode_cache_upload_enabled,
      fn parsed_data ->
        machine_metrics =
          read_machine_metrics(
            Path.join(temp_dir, "machine_metrics.jsonl"),
            parsed_data["time_started_recording"],
            parsed_data["time_stopped_recording"]
          )

        :telemetry.span([:tuist, :processor, :build, :ingest], %{}, fn ->
          result =
            parsed_data
            |> Map.drop(["time_started_recording", "time_stopped_recording"])
            |> Map.put("machine_metrics", machine_metrics)
            |> consume.()

          status = if match?({:ok, _}, result), do: :ok, else: :error
          {result, %{status: status}}
        end)
      end
    )
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
      |> Stream.map(&Map.put(&1, "offset_ms", (&1["timestamp"] - start_unix) * 1000))
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
