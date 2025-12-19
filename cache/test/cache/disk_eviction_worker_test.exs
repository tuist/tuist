defmodule Cache.DiskEvictionWorkerTest do
  use ExUnit.Case, async: false
  use Mimic

  import Ecto.Query

  alias Cache.CacheArtifact
  alias Cache.CacheArtifacts
  alias Cache.Disk
  alias Cache.DiskEvictionWorker
  alias Cache.Repo
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)

    {:ok, storage_dir} = Briefly.create(directory: true)

    stub(Disk, :storage_dir, fn -> storage_dir end)

    {:ok, storage_dir: storage_dir}
  end

  test "skips eviction when usage is below threshold", %{storage_dir: storage_dir} do
    key = "account/project/cas/file"
    path = Disk.artifact_path(key)

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, :binary.copy("a", 1024))

    :ok = CacheArtifacts.track_artifact_access(key)

    expect(Disk, :usage, fn ^storage_dir ->
      {:ok,
       %{
         total_bytes: 1_000_000,
         used_bytes: 500_000,
         available_bytes: 500_000,
         percent_used: 50.0
       }}
    end)

    assert :ok = DiskEvictionWorker.perform(%Oban.Job{args: %{}})
    assert File.exists?(path)
  end

  test "evicts least recently used artifacts when disk usage is high", %{storage_dir: storage_dir} do
    key_old = "acct/project/cas/old"
    key_new = "acct/project/cas/new"
    key_newest = "acct/project/cas/newest"

    older = Disk.artifact_path(key_old)
    newer = Disk.artifact_path(key_new)
    newest = Disk.artifact_path(key_newest)

    File.mkdir_p!(Path.dirname(older))

    File.write!(older, :binary.copy("o", 400_000))
    File.write!(newer, :binary.copy("n", 300_000))
    File.write!(newest, :binary.copy("N", 200_000))

    :ok = CacheArtifacts.track_artifact_access(key_old)
    :ok = CacheArtifacts.track_artifact_access(key_new)
    :ok = CacheArtifacts.track_artifact_access(key_newest)

    set_last_access(key_old, ~U[2024-01-01 00:00:00Z])
    set_last_access(key_new, ~U[2024-06-01 00:00:00Z])
    set_last_access(key_newest, DateTime.utc_now())

    expect(Disk, :usage, fn ^storage_dir ->
      {:ok,
       %{
         total_bytes: 1_000_000,
         used_bytes: 900_000,
         available_bytes: 100_000,
         percent_used: 90.0
       }}
    end)

    assert :ok = DiskEvictionWorker.perform(%Oban.Job{args: %{}})

    refute File.exists?(older)
    assert File.exists?(newer)
    assert File.exists?(newest)

    assert [] = Repo.all(from a in CacheArtifact, where: a.key == ^key_old)
    assert [_] = Repo.all(from a in CacheArtifact, where: a.key == ^key_new)
    assert [_] = Repo.all(from a in CacheArtifact, where: a.key == ^key_newest)
  end

  defp set_last_access(key, timestamp) do
    Repo.update_all(from(a in CacheArtifact, where: a.key == ^key),
      set: [last_accessed_at: timestamp, updated_at: timestamp]
    )

    :ok
  end
end
