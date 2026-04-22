defmodule Cache.CacheArtifactOrphanCleanupWorkerTest do
  use ExUnit.Case, async: false
  use Mimic

  import Ecto.Query

  alias Cache.CacheArtifact
  alias Cache.CacheArtifactOrphanCleanupWorker
  alias Cache.Disk
  alias Cache.Repo
  alias Ecto.Adapters.SQL.Sandbox

  @cursor_key :cache_artifact_orphan_cleanup_cursor

  setup do
    :ok = Sandbox.checkout(Repo)
    Repo.delete_all(CacheArtifact)
    Application.delete_env(:cache, @cursor_key)

    {:ok, storage_dir} = Briefly.create(directory: true)
    stub(Disk, :storage_dir, fn -> storage_dir end)

    {:ok, storage_dir: storage_dir}
  end

  test "deletes rows whose file does not exist on disk", %{storage_dir: storage_dir} do
    orphan_key = "acct/proj/xcode/AB/CD/orphan"
    present_key = "acct/proj/xcode/EF/GH/present"

    insert_artifact(orphan_key, old_timestamp())
    insert_artifact(present_key, old_timestamp())

    write_file(storage_dir, present_key)

    assert :ok = CacheArtifactOrphanCleanupWorker.perform(%Oban.Job{args: %{}})

    assert [^present_key] = Repo.all(from_keys())
  end

  test "does not delete rows younger than 1 hour", %{storage_dir: _storage_dir} do
    key = "acct/proj/xcode/IJ/KL/young"
    insert_artifact(key, DateTime.utc_now() |> DateTime.truncate(:second))

    assert :ok = CacheArtifactOrphanCleanupWorker.perform(%Oban.Job{args: %{}})

    assert [^key] = Repo.all(from_keys())
  end

  test "advances the cursor so the next run continues from where it left off" do
    assert Application.get_env(:cache, @cursor_key) in [nil, 0]

    key1 = "acct/proj/xcode/11/11/a"
    key2 = "acct/proj/xcode/22/22/b"
    insert_artifact(key1, old_timestamp())
    insert_artifact(key2, old_timestamp())

    assert :ok = CacheArtifactOrphanCleanupWorker.perform(%Oban.Job{args: %{}})

    assert Application.get_env(:cache, @cursor_key) > 0
  end

  defp insert_artifact(key, updated_at) do
    %CacheArtifact{}
    |> CacheArtifact.changeset(%{key: key, size_bytes: 7, last_accessed_at: updated_at})
    |> Ecto.Changeset.force_change(:inserted_at, updated_at)
    |> Ecto.Changeset.force_change(:updated_at, updated_at)
    |> Repo.insert!()
  end

  defp write_file(storage_dir, key) do
    path = Path.join(storage_dir, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "x")
    path
  end

  defp old_timestamp do
    DateTime.utc_now()
    |> DateTime.add(-2 * 3600, :second)
    |> DateTime.truncate(:second)
  end

  defp from_keys do
    from(a in CacheArtifact, order_by: a.id, select: a.key)
  end
end
