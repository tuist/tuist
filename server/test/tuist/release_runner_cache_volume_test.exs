defmodule Tuist.ReleaseRunnerCacheVolumeTest do
  # Not async: one test stops the application's Oban instance to reproduce a
  # release `eval` node, where none runs.
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Release
  alias Tuist.Runners
  alias Tuist.Runners.CacheVolumes
  alias Tuist.Runners.CacheVolumes.Volume
  alias Tuist.Runners.VolumeHeads
  alias Tuist.Runners.Workers.PruneVolumeMasterWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    account = AccountsFixtures.account_fixture()

    volume =
      Repo.insert!(%Volume{
        account_id: account.id,
        repository: "acme/app",
        scope_id: "123",
        key: "gradle/caches",
        architecture: "amd64",
        uid: 1001
      })

    master = String.duplicate("a", 40)
    {:ok, 1} = Runners.report_volume_head(account.id, CacheVolumes.storage_name(volume), "node", master, 0)

    %{account: account, volume: volume, master: master}
  end

  test "clears the volume and schedules the prune of its saved master", %{
    account: account,
    volume: volume,
    master: master
  } do
    name = CacheVolumes.storage_name(volume)

    assert {:ok, cleared} = Release.clear_runner_cache_volume(account.id, volume.id)

    assert cleared.generation == volume.generation + 1
    assert is_nil(cleared.head_id)
    assert cleared.deleted_at
    assert is_nil(VolumeHeads.get_head(account.id, name))
    assert_enqueued(worker: PruneVolumeMasterWorker, args: %{account_id: account.id, master_id: master})
  end

  test "clears the volume when no Oban instance runs", %{account: account, volume: volume, master: master} do
    :ok = Supervisor.terminate_child(Tuist.Supervisor, Oban)
    on_exit(fn -> {:ok, _} = Supervisor.restart_child(Tuist.Supervisor, Oban) end)

    assert {:ok, cleared} = Release.clear_runner_cache_volume(account.id, volume.id)

    assert cleared.generation == volume.generation + 1
    assert_enqueued(worker: PruneVolumeMasterWorker, args: %{account_id: account.id, master_id: master})
    assert is_nil(Oban.whereis(Oban))
  end

  test "raises when the account has no such volume", %{volume: volume} do
    other = AccountsFixtures.account_fixture()

    assert_raise RuntimeError, ~r/has no runner cache volume/, fn ->
      Release.clear_runner_cache_volume(other.id, volume.id)
    end

    assert Repo.get!(Volume, volume.id).generation == volume.generation
  end
end
