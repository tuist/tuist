defmodule Cache.OrphanCleanupWorkerTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Cache.CacheArtifact
  alias Cache.CacheArtifacts
  alias Cache.CacheArtifactsBuffer
  alias Cache.Config
  alias Cache.Disk
  alias Cache.OrphanCleanupWorker
  alias Cache.OrphanScanCursors
  alias Cache.Repo
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)

    if pid = Process.whereis(CacheArtifactsBuffer) do
      Sandbox.allow(Repo, self(), pid)
      CacheArtifactsBuffer.reset()
    end

    {:ok, storage_dir} = Briefly.create(directory: true)
    stub(Disk, :storage_dir, fn -> storage_dir end)

    {:ok, storage_dir: storage_dir}
  end

  test "deletes files on disk with no cache_artifacts row", %{storage_dir: storage_dir} do
    key = "acct/proj/cas/AB/CD/file1"
    path = write_artifact_file(storage_dir, key)

    set_old_mtime(path)
    stub(Config, :orphan_scan_max_dirs, fn -> 100 end)

    assert :ok = OrphanCleanupWorker.perform(%Oban.Job{args: %{}})
    refute File.exists?(path)
  end

  test "does NOT delete files that have a cache_artifacts row", %{storage_dir: storage_dir} do
    key = "acct/proj/cas/EF/GH/file2"
    path = write_artifact_file(storage_dir, key)

    :ok = CacheArtifacts.track_artifact_access(key)
    :ok = CacheArtifactsBuffer.flush()

    set_old_mtime(path)
    stub(Config, :orphan_scan_max_dirs, fn -> 100 end)

    assert :ok = OrphanCleanupWorker.perform(%Oban.Job{args: %{}})
    assert File.exists?(path)
  end

  test "does NOT delete files younger than 1 hour", %{storage_dir: storage_dir} do
    key = "acct/proj/cas/IJ/KL/file3"
    path = write_artifact_file(storage_dir, key)

    stub(Config, :orphan_scan_max_dirs, fn -> 100 end)

    assert :ok = OrphanCleanupWorker.perform(%Oban.Job{args: %{}})
    assert File.exists?(path)
  end

  test "skips .tmp files regardless of age", %{storage_dir: storage_dir} do
    key = "acct/proj/cas/AB/CD/.tmp.12345"
    path = write_artifact_file(storage_dir, key)

    set_old_mtime(path)
    stub(Config, :orphan_scan_max_dirs, fn -> 100 end)

    assert :ok = OrphanCleanupWorker.perform(%Oban.Job{args: %{}})
    assert File.exists?(path)
  end

  test "skips .cache-upload files regardless of age", %{storage_dir: storage_dir} do
    key = "acct/proj/cas/AB/CD/.cache-upload-67890"
    path = write_artifact_file(storage_dir, key)

    set_old_mtime(path)
    stub(Config, :orphan_scan_max_dirs, fn -> 100 end)

    assert :ok = OrphanCleanupWorker.perform(%Oban.Job{args: %{}})
    assert File.exists?(path)
  end

  test "persists cursor position after processing", %{storage_dir: storage_dir} do
    path = write_artifact_file(storage_dir, "acct/proj/cas/MM/NN/orphan")

    set_old_mtime(path)
    stub(Config, :orphan_scan_max_dirs, fn -> 1 end)

    assert :ok = OrphanCleanupWorker.perform(%Oban.Job{args: %{}})

    cursor = OrphanScanCursors.get_cursor()
    assert cursor
    assert is_binary(cursor.cursor_path)
  end

  test "resumes from cursor position on next run", %{storage_dir: storage_dir} do
    keys = [
      "acct/proj/cas/AA/AA/file-a",
      "acct/proj/cas/BB/BB/file-b",
      "acct/proj/cas/CC/CC/file-c"
    ]

    paths =
      Enum.map(keys, fn key ->
        path = write_artifact_file(storage_dir, key)
        set_old_mtime(path)
        path
      end)

    stub(Config, :orphan_scan_max_dirs, fn -> 1 end)

    assert :ok = OrphanCleanupWorker.perform(%Oban.Job{args: %{}})
    assert OrphanScanCursors.get_cursor()

    deleted_after_first_run = Enum.count(paths, fn path -> not File.exists?(path) end)
    assert deleted_after_first_run == 1

    assert :ok = OrphanCleanupWorker.perform(%Oban.Job{args: %{}})

    deleted_after_second_run = Enum.count(paths, fn path -> not File.exists?(path) end)
    assert deleted_after_second_run == 2
  end

  test "resets cursor when full pass completes", %{storage_dir: storage_dir} do
    path = write_artifact_file(storage_dir, "acct/proj/cas/DD/EE/file-reset")

    set_old_mtime(path)
    stub(Config, :orphan_scan_max_dirs, fn -> 100 end)

    assert :ok = OrphanCleanupWorker.perform(%Oban.Job{args: %{}})

    cursor = OrphanScanCursors.get_cursor()
    assert cursor.cursor_path == nil
    assert cursor.last_completed_at
  end

  test "handles deleted directory gracefully", %{storage_dir: storage_dir} do
    key = "acct/proj/cas/AA/BB/will-disappear"
    path = write_artifact_file(storage_dir, key)
    shard_dir = Path.dirname(path)

    File.rm_rf!(shard_dir)
    stub(Config, :orphan_scan_max_dirs, fn -> 100 end)

    assert :ok = OrphanCleanupWorker.perform(%Oban.Job{args: %{}})
  end

  test "handles empty storage directory", %{storage_dir: _storage_dir} do
    stub(Config, :orphan_scan_max_dirs, fn -> 100 end)

    assert :ok = OrphanCleanupWorker.perform(%Oban.Job{args: %{}})
  end

  test "respects max_dirs_per_run configuration", %{storage_dir: storage_dir} do
    keys =
      Enum.map(1..10, fn idx ->
        shard = idx |> Integer.to_string() |> String.pad_leading(2, "0")
        "acct/proj/cas/#{shard}/#{shard}/file-#{idx}"
      end)

    paths =
      Enum.map(keys, fn key ->
        path = write_artifact_file(storage_dir, key)
        set_old_mtime(path)
        path
      end)

    stub(Config, :orphan_scan_max_dirs, fn -> 3 end)

    assert :ok = OrphanCleanupWorker.perform(%Oban.Job{args: %{}})

    deleted_count = Enum.count(paths, fn path -> not File.exists?(path) end)
    remaining_count = Enum.count(paths, &File.exists?/1)

    assert deleted_count <= 3
    assert remaining_count >= 7
  end

  test "does not modify cache_artifacts table", %{storage_dir: storage_dir} do
    orphan_keys = [
      "acct/proj/cas/11/11/orphan-1",
      "acct/proj/cas/22/22/orphan-2"
    ]

    tracked_keys = [
      "acct/proj/cas/33/33/tracked-1",
      "acct/proj/cas/44/44/tracked-2"
    ]

    orphan_paths =
      Enum.map(orphan_keys, fn key ->
        path = write_artifact_file(storage_dir, key)
        set_old_mtime(path)
        path
      end)

    tracked_paths =
      Enum.map(tracked_keys, fn key ->
        path = write_artifact_file(storage_dir, key)
        :ok = CacheArtifacts.track_artifact_access(key)
        set_old_mtime(path)
        path
      end)

    :ok = CacheArtifactsBuffer.flush()
    stub(Config, :orphan_scan_max_dirs, fn -> 100 end)

    assert :ok = OrphanCleanupWorker.perform(%Oban.Job{args: %{}})

    assert Repo.aggregate(CacheArtifact, :count, :id) == 2

    assert Enum.all?(tracked_paths, &File.exists?/1)
    assert Enum.all?(orphan_paths, fn path -> not File.exists?(path) end)
  end

  defp write_artifact_file(storage_dir, key) do
    path = Path.join(storage_dir, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "content")
    path
  end

  defp set_old_mtime(path) do
    # File.touch!/2 accepts POSIX timestamps (seconds since epoch)
    two_hours_ago = System.os_time(:second) - 7200
    File.touch!(path, two_hours_ago)
  end
end
