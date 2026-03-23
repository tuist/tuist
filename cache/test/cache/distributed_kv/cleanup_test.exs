defmodule Cache.DistributedKV.CleanupTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Cache.Config
  alias Cache.DistributedKV.Cleanup
  alias Cache.DistributedKV.Entry
  alias Cache.DistributedKV.Project
  alias Cache.DistributedKV.Repo

  setup :set_mimic_from_context

  setup do
    stub(Config, :distributed_kv_cleanup_lease_ms, fn -> 60_000 end)
    :ok
  end

  test "concurrent cleanup requests reuse the persisted cutoff" do
    {:ok, cleanup_agent} = Agent.start_link(fn -> nil end)
    parent = self()

    stub(Repo, :insert, fn %Project{account_handle: "acme", project_handle: "ios"} = struct, opts ->
      assert opts[:conflict_target] == [:account_handle, :project_handle]
      assert opts[:returning] == true

      Agent.get_and_update(cleanup_agent, fn
        nil ->
          {{:ok, struct}, struct}

        %Project{} = existing ->
          {{:ok, existing}, existing}
      end)
    end)

    task_fun = fn ->
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

    assert {:ok, cutoff_1} = Task.await(task_1)
    assert {:ok, cutoff_2} = Task.await(task_2)
    assert DateTime.compare(cutoff_1, cutoff_2) == :eq

    assert %Project{last_cleanup_at: persisted_cutoff} = Agent.get(cleanup_agent, & &1)
    assert persisted_cutoff == cutoff_1
  end

  test "expired cleanup leases get a fresh cutoff" do
    stale_cutoff = DateTime.add(DateTime.utc_now(), -120, :second)
    stale_lease = DateTime.add(DateTime.utc_now(), -60, :second)

    stale_cleanup = %Project{
      account_handle: "acme",
      project_handle: "ios",
      last_cleanup_at: stale_cutoff,
      cleanup_lease_expires_at: stale_lease,
      updated_at: stale_cutoff
    }

    {:ok, cleanup_agent} = Agent.start_link(fn -> stale_cleanup end)

    stub(Repo, :insert, fn %Project{} = struct, _opts ->
      Agent.get_and_update(cleanup_agent, fn %Project{cleanup_lease_expires_at: current_lease} = existing ->
        now = DateTime.utc_now()

        if DateTime.after?(current_lease, now) do
          {{:ok, existing}, existing}
        else
          {{:ok, struct}, struct}
        end
      end)
    end)

    assert {:ok, fresh_cutoff} = Cleanup.begin_project_cleanup("acme", "ios")
    assert DateTime.after?(fresh_cutoff, stale_cutoff)

    assert %Project{last_cleanup_at: persisted_cutoff, cleanup_lease_expires_at: persisted_lease} =
             Agent.get(cleanup_agent, & &1)

    assert persisted_cutoff == fresh_cutoff
    assert DateTime.after?(persisted_lease, fresh_cutoff)
  end

  test "renew_project_cleanup_lease extends the active lease for the same cleanup" do
    cutoff = DateTime.utc_now()

    expect(Repo, :update_all, fn _query, updates ->
      [set: set_values] = updates
      assert DateTime.after?(set_values[:cleanup_lease_expires_at], cutoff)
      assert %DateTime{} = set_values[:updated_at]
      {1, nil}
    end)

    assert :ok = Cleanup.renew_project_cleanup_lease("acme", "ios", cutoff)
  end

  test "renew_project_cleanup_lease reports when the lease is no longer active" do
    cutoff = DateTime.utc_now()

    expect(Repo, :update_all, fn _query, _updates ->
      {0, nil}
    end)

    assert {:error, :cleanup_lease_lost} = Cleanup.renew_project_cleanup_lease("acme", "ios", cutoff)
  end

  test "tombstone_project_entries keeps microsecond precision in updated_at" do
    cutoff = ~U[2026-03-12 12:00:00.123456Z]

    expect(Repo, :update_all, fn _query, updates ->
      [set: set_values] = updates
      assert set_values[:deleted_at] == cutoff
      assert Entry.__schema__(:type, :updated_at) == :utc_datetime_usec
      assert {:ok, _} = Ecto.Type.dump(Entry.__schema__(:type, :updated_at), set_values[:updated_at])
      {1, nil}
    end)

    assert 1 == Cleanup.tombstone_project_entries("acme", "ios", cutoff)
  end
end
