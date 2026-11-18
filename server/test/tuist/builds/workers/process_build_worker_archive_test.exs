defmodule Tuist.Builds.Workers.ProcessBuildWorkerArchiveTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Builds
  alias Tuist.Builds.Workers.ProcessBuildWorker
  alias Tuist.Processor.XCActivityLogParser
  alias Tuist.Projects
  alias Tuist.Storage

  @build_id "00000000-0000-4000-8000-000000000001"
  @log_name ~c"xcactivitylog/build.xcactivitylog"

  # One CLI sample inside the recording window (Apple reference time 0.125..1.325).
  @sample ~s({"timestamp":978307200.625,"cpu_usage_percent":50,"memory_used_bytes":1,"memory_total_bytes":2,) <>
            ~s("network_bytes_in":3,"network_bytes_out":4,"disk_bytes_read":5,"disk_bytes_written":6,) <>
            ~s("disk_total_bytes":500000000000,"disk_available_bytes":125000000000})

  setup :verify_on_exit!

  setup context do
    metrics_entries =
      case context[:machine_metrics] do
        nil -> []
        :over_cap -> [{~c"machine_metrics.jsonl", @sample <> "\n" <> :binary.copy(" ", 32 * 1024 * 1024)}]
        jsonl -> [{~c"machine_metrics.jsonl", jsonl}]
      end

    {:ok, {_, archive}} =
      :zip.create(~c"build.zip", [{@log_name, "original activity log"} | metrics_entries], [:memory, {:compress, []}])

    archive =
      case context[:archive_error] do
        :bad_eocd -> binary_part(archive, 0, byte_size(archive) - 22)
        :bad_crc -> :binary.replace(archive, "original activity log", "modified activity log")
        nil -> archive
      end

    expect(Projects, :get_project_by_id, fn 123 -> %{account: %{id: 456}} end)

    expect(Storage, :download_to_file, fn "build.zip", path, %{id: 456} ->
      File.write!(path, archive)
      send(self(), {:download_path, path})
      {:ok, :done}
    end)

    :ok
  end

  for archive_error <- [:bad_eocd, :bad_crc] do
    @tag archive_error: archive_error
    test "discards #{archive_error} on the first attempt and marks the build as failed" do
      reject(&XCActivityLogParser.parse/5)
      expect(Builds, :get_build, fn @build_id, [project_id: 123] -> {:error, :not_found} end)

      expect(Builds, :create_build, fn attrs ->
        assert attrs.id == @build_id
        assert attrs.project_id == 123
        assert attrs.account_id == 789
        assert attrs.status == "failed_processing"
        assert attrs.duration == 0
        {:ok, attrs}
      end)

      assert {:discard, :corrupt_archive} = ProcessBuildWorker.perform(job(1))

      assert_received {:download_path, path}
      refute File.exists?(path)
    end
  end

  test "continues to parse valid archives and cleans up the extracted files" do
    expect(XCActivityLogParser, :parse, fn path, _, _, false, consume ->
      assert File.read!(path) == "original activity log"
      send(self(), {:extracted_path, path})

      consume.(%{
        "status" => "success",
        "duration" => 1200,
        "time_started_recording" => 0.125,
        "time_stopped_recording" => 1.325
      })
    end)

    expect(Builds, :get_build, fn @build_id, [project_id: 123] -> {:error, :not_found} end)

    expect(Builds, :create_build, fn attrs ->
      assert attrs.status == "success"
      assert attrs.duration == 1200
      assert attrs.started_at == ~N[2001-01-01 00:00:00.125000]
      {:ok, attrs}
    end)

    assert :ok = ProcessBuildWorker.perform(job(1))

    assert_received {:download_path, download_path}
    assert_received {:extracted_path, extracted_path}
    refute File.exists?(download_path)
    refute File.exists?(Path.dirname(extracted_path))
  end

  @tag machine_metrics: @sample <> "\n"
  test "ingests machine metric samples from the archive" do
    stub_parse_and_get_build()

    expect(Builds, :create_build, fn attrs ->
      assert [sample] = attrs.machine_metrics
      assert sample.timestamp == 978_307_200.625
      assert sample.offset_ms == 500.0
      assert sample.cpu_usage_percent == 50
      assert sample.disk_bytes_written == 6
      assert sample.disk_total_bytes == 500_000_000_000
      assert sample.disk_available_bytes == 125_000_000_000
      {:ok, attrs}
    end)

    assert :ok = ProcessBuildWorker.perform(job(1))
  end

  # The same valid sample, padded with a blank line to just over the 32 MiB cap.
  @tag machine_metrics: :over_cap
  test "skips a machine metrics file larger than the cap and still processes the build" do
    stub_parse_and_get_build()

    expect(Builds, :create_build, fn attrs ->
      assert attrs.status == "success"
      assert attrs.machine_metrics == []
      {:ok, attrs}
    end)

    assert :ok = ProcessBuildWorker.perform(job(1))
  end

  defp stub_parse_and_get_build do
    expect(XCActivityLogParser, :parse, fn _path, _, _, false, consume ->
      consume.(%{
        "status" => "success",
        "duration" => 1200,
        "time_started_recording" => 0.125,
        "time_stopped_recording" => 1.325
      })
    end)

    expect(Builds, :get_build, fn @build_id, [project_id: 123] -> {:error, :not_found} end)
  end

  defp job(attempt) do
    %Oban.Job{
      args: %{
        "build_id" => @build_id,
        "storage_key" => "build.zip",
        "project_id" => 123,
        "account_id" => 789
      },
      attempt: attempt,
      max_attempts: 5
    }
  end
end
