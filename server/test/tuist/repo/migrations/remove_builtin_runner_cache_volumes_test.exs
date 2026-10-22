Code.require_file(
  Path.expand("../../../../priv/repo/migrations/20261022120000_remove_builtin_runner_cache_volumes.exs", __DIR__)
)

defmodule Tuist.Repo.Migrations.RemoveBuiltinRunnerCacheVolumesTest do
  use TuistTestSupport.Cases.DataCase, async: false

  import Ecto.Query

  alias Tuist.Repo.Migrations.RemoveBuiltinRunnerCacheVolumes
  alias Tuist.Runners.CacheVolumes.Measurement
  alias Tuist.Runners.CacheVolumes.Usage
  alias Tuist.Runners.CacheVolumes.Volume
  alias Tuist.Runners.VolumeHead
  alias Tuist.Runners.VolumeMasterOrphan
  alias Tuist.Runners.Workers.PurgeBuiltinVolumeMastersWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @custom "macos-" <> String.duplicate("a", 64)

  setup do
    # excellent_migrations:safety-assured-for-next-line operation_query
    Repo.query!("CREATE TABLE IF NOT EXISTS runner_volume_affinities (account_id bigint NOT NULL)")
    :ok
  end

  test "queues a storage purge for every account that may hold built-in masters" do
    builtin = AccountsFixtures.account_fixture()
    affine = AccountsFixtures.account_fixture()
    macos = AccountsFixtures.account_fixture()
    custom = AccountsFixtures.account_fixture()

    head(builtin.id, "tuist-cache")
    head(builtin.id, "repo-0123456789abcdef")
    head(custom.id, @custom)
    # excellent_migrations:safety-assured-for-next-line operation_query
    Repo.query!("INSERT INTO runner_volume_affinities (account_id) VALUES ($1)", [affine.id])
    session(macos.id, "macos")
    session(custom.id, "linux")

    RemoveBuiltinRunnerCacheVolumes.enqueue_purges!(Repo)

    account_ids =
      [worker: PurgeBuiltinVolumeMastersWorker]
      |> all_enqueued()
      |> Enum.map(fn %{args: %{"account_id" => id}, queue: "default", max_attempts: 20} -> id end)
      |> Enum.sort()

    assert account_ids == Enum.sort([builtin.id, affine.id, macos.id])
  end

  test "deletes only built-in rows, cascading to their uses and measurements" do
    account = AccountsFixtures.account_fixture()
    head(account.id, "tuist-cache")
    head(account.id, "repo-0123456789abcdef")
    head(account.id, @custom)
    orphan(account.id, "tuist-cache")
    orphan(account.id, @custom)
    builtin_volume = volume(account.id, "tuist-cache")
    custom_volume = volume(account.id, nil)

    for statement <- RemoveBuiltinRunnerCacheVolumes.cleanup_statements() do
      # excellent_migrations:safety-assured-for-next-line operation_query
      Repo.query!(statement)
    end

    # excellent_migrations:safety-assured-for-next-line operation_all
    assert Repo.all(from(h in VolumeHead, select: h.volume_name)) == [@custom]
    # excellent_migrations:safety-assured-for-next-line operation_all
    assert Repo.all(from(o in VolumeMasterOrphan, select: o.volume_name)) == [@custom]
    # excellent_migrations:safety-assured-for-next-line operation_all
    assert Repo.all(from(v in Volume, select: v.id)) == [custom_volume]
    # excellent_migrations:safety-assured-for-next-line operation_all
    assert Repo.all(from(u in Usage, select: u.volume_id)) == [custom_volume]
    # excellent_migrations:safety-assured-for-next-line operation_aggregate
    assert Repo.aggregate(Measurement, :count) == 1
    refute builtin_volume == custom_volume
  end

  defp head(account_id, volume_name) do
    now = DateTime.utc_now(:second)

    # excellent_migrations:safety-assured-for-next-line operation_insert
    Repo.insert_all(VolumeHead, [
      %{
        account_id: account_id,
        volume_name: volume_name,
        tree_digest: "d",
        generation: 1,
        inserted_at: now,
        updated_at: now
      }
    ])
  end

  defp orphan(account_id, volume_name) do
    now = DateTime.utc_now(:second)

    # excellent_migrations:safety-assured-for-next-line operation_insert
    Repo.insert_all(VolumeMasterOrphan, [
      %{account_id: account_id, volume_name: volume_name, tree_digest: "o", inserted_at: now, updated_at: now}
    ])
  end

  defp session(account_id, platform) do
    now = DateTime.utc_now(:second)

    # excellent_migrations:safety-assured-for-next-line operation_insert
    Repo.insert_all("runner_sessions", [
      %{
        account_id: account_id,
        workflow_job_id: System.unique_integer([:positive]),
        fleet_name: "fleet",
        pod_name: "pod",
        node_name: "node",
        runner_name: "runner",
        platform: platform,
        vcpus: 4,
        memory_gb: 16,
        billing_multiplier: 10_000,
        started_at: now,
        inserted_at: now,
        updated_at: now
      }
    ])
  end

  defp volume(account_id, builtin_name) do
    now = DateTime.utc_now(:second)
    id = Ecto.UUID.generate()
    key = builtin_name || "tuist-xcode"

    # excellent_migrations:safety-assured-for-next-line operation_insert
    Repo.insert_all("runner_cache_volumes", [
      %{
        id: Ecto.UUID.dump!(id),
        account_id: account_id,
        builtin_name: builtin_name,
        provider: "github",
        provider_instance: "github.com",
        scope_id: key,
        repository: "acme/app",
        repository_id: 0,
        key: key,
        platform: "macos",
        architecture: "arm64",
        uid: 501,
        inserted_at: now,
        updated_at: now
      }
    ])

    attrs = %Usage{
      volume_id: id,
      generation: 1,
      pod_name: "pod",
      pod_uid: "pod-#{key}",
      node_name: "node",
      workflow_job_id: 1,
      workflow_run_id: 1,
      can_publish: false
    }

    # excellent_migrations:safety-assured-for-next-line operation_insert
    usage = Repo.insert!(attrs)

    # excellent_migrations:safety-assured-for-next-line operation_insert
    Repo.insert!(%Measurement{usage_id: usage.id, size_bytes: 1, capacity_bytes: 2, observed_at: DateTime.utc_now()})

    id
  end
end
