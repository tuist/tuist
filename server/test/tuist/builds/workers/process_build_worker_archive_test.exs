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

  setup :verify_on_exit!

  setup context do
    {:ok, {_, archive}} =
      :zip.create(~c"build.zip", [{@log_name, "original activity log"}], [:memory, {:compress, []}])

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

  for {archive_error, reason} <- [bad_eocd: :bad_eocd, bad_crc: {@log_name, :bad_crc}] do
    @tag archive_error: archive_error
    test "retries #{archive_error} without marking the build as failed" do
      reject(&XCActivityLogParser.parse/4)
      reject(&Builds.create_build/1)

      assert {:error, unquote(Macro.escape(reason))} = ProcessBuildWorker.perform(job(1))

      assert_received {:download_path, path}
      refute File.exists?(path)
    end

    @tag archive_error: archive_error
    test "marks the build as failed after exhausting retries for #{archive_error}" do
      reject(&XCActivityLogParser.parse/4)
      expect(Builds, :get_build, fn @build_id, [project_id: 123] -> {:error, :not_found} end)

      expect(Builds, :create_build, fn attrs ->
        assert attrs.id == @build_id
        assert attrs.project_id == 123
        assert attrs.account_id == 789
        assert attrs.status == "failed_processing"
        assert attrs.duration == 0
        {:ok, attrs}
      end)

      assert {:error, unquote(Macro.escape(reason))} = ProcessBuildWorker.perform(job(5))

      assert_received {:download_path, path}
      refute File.exists?(path)
    end
  end

  test "continues to parse valid archives and cleans up the extracted files" do
    expect(XCActivityLogParser, :parse, fn path, _, _, false ->
      assert File.read!(path) == "original activity log"
      send(self(), {:extracted_path, path})
      {:ok, %{"status" => "success", "duration" => 1200}}
    end)

    expect(Builds, :get_build, fn @build_id, [project_id: 123] -> {:error, :not_found} end)

    expect(Builds, :create_build, fn attrs ->
      assert attrs.status == "success"
      assert attrs.duration == 1200
      {:ok, attrs}
    end)

    assert :ok = ProcessBuildWorker.perform(job(1))

    assert_received {:download_path, download_path}
    assert_received {:extracted_path, extracted_path}
    refute File.exists?(download_path)
    refute File.exists?(Path.dirname(extracted_path))
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
