defmodule Cache.DistributedKV.CleanupTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Cache.Config
  alias Cache.DistributedKV.Cleanup
  alias Cache.DistributedKV.Entry
  alias Cache.DistributedKV.Project
  alias Cache.DistributedKV.Repo
  alias Ecto.Adapters.SQL.Sandbox

  setup :set_mimic_from_context

  setup_all do
    ensure_distributed_repo_storage!()

    case start_supervised(Repo) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    {:ok, _, _} = Ecto.Migrator.with_repo(Repo, &Ecto.Migrator.run(&1, :up, all: true))

    :ok
  end

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
    Repo.delete_all(Entry)
    Repo.delete_all(Project)
    stub(Config, :distributed_kv_cleanup_lease_ms, fn -> 60_000 end)
    :ok
  end

  test "concurrent cleanup requests reject overlapping workers" do
    parent = self()

    task_fun = fn ->
      Sandbox.allow(Repo, parent, self())
      send(parent, {:ready, self()})

      receive do
        :go -> Cleanup.begin_project_cleanup("acme", "ios")
      end
    end

    task_1 = Task.async(task_fun)
    task_2 = Task.async(task_fun)

    ready_pids =
      for _ <- 1..2 do
        assert_receive {:ready, pid}
        pid
      end

    Enum.each(ready_pids, &send(&1, :go))

    results = [Task.await(task_1), Task.await(task_2)]

    assert Enum.count(results, &match?({:ok, %DateTime{}}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :cleanup_already_in_progress})) == 1

    assert 1 == Repo.aggregate(Project, :count)
  end

  test "expired cleanup leases get a fresh cutoff" do
    stale_cutoff = DateTime.add(DateTime.utc_now(), -120, :second)
    stale_lease = DateTime.add(DateTime.utc_now(), -60, :second)

    Repo.insert!(%Project{
      account_handle: "acme",
      project_handle: "ios",
      last_cleanup_at: stale_cutoff,
      cleanup_lease_expires_at: stale_lease,
      updated_at: stale_cutoff
    })

    assert {:ok, fresh_cutoff} = Cleanup.begin_project_cleanup("acme", "ios")
    assert DateTime.after?(fresh_cutoff, stale_cutoff)

    assert %Project{last_cleanup_at: persisted_cutoff, cleanup_lease_expires_at: persisted_lease} =
             Repo.get_by!(Project, account_handle: "acme", project_handle: "ios")

    assert persisted_cutoff == fresh_cutoff
    assert DateTime.after?(persisted_lease, fresh_cutoff)
  end

  test "renew_project_cleanup_lease extends the active lease for the same cleanup" do
    now = DateTime.utc_now()
    cutoff = DateTime.add(now, -5, :second)
    initial_lease = DateTime.add(now, 10, :second)

    Repo.insert!(%Project{
      account_handle: "acme",
      project_handle: "ios",
      last_cleanup_at: cutoff,
      cleanup_lease_expires_at: initial_lease,
      updated_at: cutoff
    })

    assert :ok = Cleanup.renew_project_cleanup_lease("acme", "ios", cutoff)

    renewed = Repo.get_by!(Project, account_handle: "acme", project_handle: "ios")
    assert DateTime.after?(renewed.cleanup_lease_expires_at, initial_lease)
    assert DateTime.after?(renewed.updated_at, cutoff)
  end

  test "renew_project_cleanup_lease reports when the lease is no longer active" do
    cutoff = DateTime.utc_now()

    Repo.insert!(%Project{
      account_handle: "acme",
      project_handle: "ios",
      last_cleanup_at: cutoff,
      cleanup_lease_expires_at: DateTime.add(cutoff, -1, :second),
      updated_at: cutoff
    })

    assert {:error, :cleanup_lease_lost} = Cleanup.renew_project_cleanup_lease("acme", "ios", cutoff)
  end

  test "latest_project_cleanup_cutoffs matches only the requested project pairs" do
    ios_cutoff = ~U[2026-03-12 12:00:00.000000Z]
    android_cutoff = ~U[2026-03-12 13:00:00.000000Z]
    beta_cutoff = ~U[2026-03-12 14:00:00.000000Z]

    Repo.insert!(%Project{
      account_handle: "acme",
      project_handle: "ios",
      last_cleanup_at: ios_cutoff,
      cleanup_lease_expires_at: DateTime.add(ios_cutoff, 60, :second),
      updated_at: ios_cutoff
    })

    Repo.insert!(%Project{
      account_handle: "acme",
      project_handle: "android",
      last_cleanup_at: android_cutoff,
      cleanup_lease_expires_at: DateTime.add(android_cutoff, 60, :second),
      updated_at: android_cutoff
    })

    Repo.insert!(%Project{
      account_handle: "beta",
      project_handle: "ios",
      last_cleanup_at: beta_cutoff,
      cleanup_lease_expires_at: DateTime.add(beta_cutoff, 60, :second),
      updated_at: beta_cutoff
    })

    cutoffs =
      Cleanup.latest_project_cleanup_cutoffs([
        %{account_handle: "acme", project_handle: "ios"},
        %{account_handle: "beta", project_handle: "ios"},
        %{account_handle: "acme", project_handle: "ios"}
      ])

    assert cutoffs == %{
             {"acme", "ios"} => DateTime.truncate(ios_cutoff, :second),
             {"beta", "ios"} => DateTime.truncate(beta_cutoff, :second)
           }
  end

  test "expire_project_cleanup_lease releases the active lease for retries" do
    now = DateTime.utc_now()
    cutoff = DateTime.add(now, -5, :second)

    Repo.insert!(%Project{
      account_handle: "acme",
      project_handle: "ios",
      last_cleanup_at: cutoff,
      cleanup_lease_expires_at: DateTime.add(now, 60, :second),
      updated_at: cutoff
    })

    assert :ok = Cleanup.expire_project_cleanup_lease("acme", "ios", cutoff)

    expired = Repo.get_by!(Project, account_handle: "acme", project_handle: "ios")
    assert DateTime.compare(expired.cleanup_lease_expires_at, DateTime.utc_now()) in [:lt, :eq]

    assert {:ok, fresh_cutoff} = Cleanup.begin_project_cleanup("acme", "ios")
    assert DateTime.after?(fresh_cutoff, cutoff)
  end

  test "tombstone_project_entries keeps microsecond precision in updated_at" do
    cutoff = ~U[2026-03-12 12:00:00.123456Z]

    Repo.insert!(%Entry{
      key: "keyvalue:acme:ios:artifact",
      account_handle: "acme",
      project_handle: "ios",
      cas_id: "artifact",
      json_payload: Jason.encode!(%{entries: []}),
      source_node: "node-a",
      source_updated_at: cutoff,
      last_accessed_at: cutoff,
      updated_at: cutoff
    })

    assert 1 == Cleanup.tombstone_project_entries("acme", "ios", cutoff)

    assert %Entry{deleted_at: ^cutoff, updated_at: updated_at} = Repo.get!(Entry, "keyvalue:acme:ios:artifact")
    assert Entry.__schema__(:type, :updated_at) == :utc_datetime_usec
    assert {:ok, _} = Ecto.Type.dump(Entry.__schema__(:type, :updated_at), updated_at)
    assert elem(updated_at.microsecond, 1) == 6
  end

  defp ensure_distributed_repo_storage! do
    case Repo.__adapter__().storage_up(Repo.config()) do
      :ok -> :ok
      {:error, :already_up} -> :ok
      {:error, reason} -> raise "failed to create distributed KV test database: #{inspect(reason)}"
    end
  end
end
