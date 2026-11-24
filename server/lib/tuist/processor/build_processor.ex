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
  alias Tuist.Processor.ZipExtractor

  require Logger

  @apple_reference_date_offset 978_307_200

  # The CLI samples once per second and trims the file to the last hour, about
  # 1 MB. The file comes from the uploaded archive and every decoded line is
  # kept in memory, so a far larger file is skipped rather than read: a small,
  # highly compressed archive could otherwise exhaust the processor's memory.
  @max_machine_metrics_bytes 32 * 1024 * 1024

  # An archive holds one activity log, the CAS analytics database, a log tail
  # and the machine metrics, or a legacy `cas_metadata` directory of small
  # files. Build processors unzip into a 16 GiB /tmp shared by five slots, sized
  # at about 3 GiB for any realistic archive (`infra/helm/tuist/values.yaml`),
  # so one slot's share is the limit: concurrent zip bombs cannot fill the disk.
  # Raise it together with `tmpSizeLimit`.
  @max_extracted_bytes 3 * 1024 * 1024 * 1024
  @max_extracted_entries 100_000

  # Reasons the extraction returns when the archive itself is malformed, taken
  # from the atoms `stdlib`'s `zip.erl` actually throws. The download layer
  # guarantees the object was fully written before we open it, so these are
  # customer-side bad uploads (truncated by the client, wrong bytes, or
  # already corrupt on their disk) rather than a transport problem. Callers
  # surface them as `{:error, :corrupt_archive}` and skip retrying.
  @corrupt_archive_zip_reasons ~w(
    bad_eocd
    bad_eocd64
    bad_central_directory
    bad_local_file_header
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
    case ZipExtractor.extract(zip_path, temp_dir, max_bytes: @max_extracted_bytes, max_entries: @max_extracted_entries) do
      :ok ->
        process_extracted_build(temp_dir, xcode_cache_upload_enabled, consume)

      {:error, :archive_too_large} = error ->
        error

      {:error, reason} when reason in @corrupt_archive_zip_reasons ->
        {:error, :corrupt_archive}

      # `bad_local_file_header` is thrown both bare and as `{bad_local_file_header, Else}`
      # depending on where the parser rejected the entry, and per-entry failures
      # arrive as `{FileName, :bad_crc}` when the recorded checksum doesn't
      # match the entry bytes. Same class of problem as a bad EOCD: the
      # customer's upload is corrupt and retries won't heal it.
      {:error, {:bad_local_file_header, _}} ->
        {:error, :corrupt_archive}

      {:error, {_file, :bad_crc}} ->
        {:error, :corrupt_archive}

      {:error, {:unsafe_entry_name, _}} ->
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
            |> Map.put("started_at", build_started_at(parsed_data["time_started_recording"]))
            |> Map.drop(["time_started_recording", "time_stopped_recording"])
            |> Map.put("machine_metrics", machine_metrics)
            |> consume.()

          status = if match?({:ok, _}, result), do: :ok, else: :error
          {result, %{status: status}}
        end)
      end
    )
  end

  defp build_started_at(nil), do: nil

  defp build_started_at(apple_timestamp) do
    apple_timestamp
    |> Kernel.*(1_000_000)
    |> round()
    |> Kernel.+(@apple_reference_date_offset * 1_000_000)
    |> DateTime.from_unix!(:microsecond)
    |> DateTime.to_naive()
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
    case File.stat(path) do
      {:ok, %{size: size}} when size > @max_machine_metrics_bytes ->
        Logger.warning("Skipping machine metrics: machine_metrics.jsonl is #{size} bytes")
        []

      {:ok, _} ->
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

      {:error, _} ->
        []
    end
  end

  defp cleanup_temp(temp_dir) do
    File.rm_rf(temp_dir)
    :ok
  end
end
