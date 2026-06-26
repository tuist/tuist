defmodule Tuist.Processor.BuildProcessor do
  @moduledoc """
  Parses xcactivitylog build archives.

  The server's `ProcessBuildWorker` Oban job is the only caller: it downloads
  the archive from S3 into a temp file, hands the path to `process_build/2`,
  writes the returned structured data to the DB, and deletes the temp file.

  On processor-mode pods (`TUIST_MODE=processor`) this runs as the Oban
  worker body — the CPU-heavy parse work is scheduled onto dedicated replicas
  rather than every web server pod. On self-hosted installs it runs in the
  same BEAM as the rest of the server.
  """

  @apple_reference_date_offset 978_307_200

  # Entries that are safe to drop from a build archive when their CRC is bad.
  # `machine_metrics.jsonl` is optional telemetry the CLI bundles from a copy of
  # a file an always-on sampler daemon keeps writing; a corrupt copy there must
  # not sink an otherwise-parseable build. Critical entries (the xcactivitylog,
  # the CAS databases) are intentionally absent so their corruption still fails
  # loudly and the Oban job retries.
  @non_critical_archive_files ["machine_metrics.jsonl"]

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
    {:ok, _} = unzip_tolerating_bad_crc(zip_path, temp_dir)
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

  # `:zip.unzip` is all-or-nothing: a single entry with a bad CRC aborts the
  # whole extraction. When the corrupt entry is a non-critical archive file we
  # re-extract with it filtered out so the build still processes; a bad CRC on
  # any other entry is returned unchanged so the caller fails loudly (and the
  # Oban job retries), exactly as it did before.
  defp unzip_tolerating_bad_crc(zip_path, temp_dir, excluded \\ []) do
    file_filter = fn {:zip_file, name, _info, _comment, _offset, _comp_size} ->
      to_string(name) not in excluded
    end

    case :zip.unzip(~c"#{zip_path}", [{:cwd, ~c"#{temp_dir}"}, {:file_filter, file_filter}]) do
      {:ok, _} = result ->
        result

      {:error, reason} = error ->
        name = bad_crc_file(reason)

        if name in @non_critical_archive_files and name not in excluded do
          # `:zip.unzip` writes each entry to disk before verifying its CRC, so the
          # corrupt file is left behind by the aborted pass. Remove it so the
          # filtered retry doesn't leave known-bad bytes for later readers.
          File.rm(Path.join(temp_dir, name))
          unzip_tolerating_bad_crc(zip_path, temp_dir, [name | excluded])
        else
          error
        end
    end
  end

  # The tuple order of `:bad_crc` errors differs across OTP releases
  # (`{:bad_crc, name}` on OTP 28, `{name, :bad_crc}` on older releases), so we
  # match both shapes and return the offending entry name as a string.
  defp bad_crc_file({:bad_crc, name}), do: to_string(name)
  defp bad_crc_file({name, :bad_crc}), do: to_string(name)
  defp bad_crc_file(_), do: nil

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
