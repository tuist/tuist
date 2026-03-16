defmodule Cache.DistributedKV.CleanupTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Cache.DistributedKV.Cleanup
  alias Cache.DistributedKV.ProjectCleanup
  alias Cache.DistributedKV.Repo

  setup :set_mimic_from_context

  setup do
    original_lease_ms = Application.get_env(:cache, :distributed_kv_cleanup_lease_ms)
    Application.put_env(:cache, :distributed_kv_cleanup_lease_ms, 60_000)

    on_exit(fn ->
      Application.put_env(:cache, :distributed_kv_cleanup_lease_ms, original_lease_ms)
    end)

    :ok
  end

  test "concurrent cleanup requests reuse the persisted cutoff" do
    {:ok, cleanup_agent} = Agent.start_link(fn -> nil end)
    parent = self()

    stub(Repo, :insert, fn %ProjectCleanup{account_handle: "acme", project_handle: "ios"} = struct, opts ->
      assert opts[:conflict_target] == [:account_handle, :project_handle]
      assert opts[:returning] == true

      Agent.get_and_update(cleanup_agent, fn
        nil ->
          {{:ok, struct}, struct}

        %ProjectCleanup{} = existing ->
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

    assert %ProjectCleanup{cleanup_started_at: persisted_cutoff} = Agent.get(cleanup_agent, & &1)
    assert persisted_cutoff == cutoff_1
  end

  test "expired cleanup leases get a fresh cutoff" do
    stale_cutoff = DateTime.add(DateTime.utc_now(), -120, :second)
    stale_lease = DateTime.add(DateTime.utc_now(), -60, :second)

    stale_cleanup = %ProjectCleanup{
      account_handle: "acme",
      project_handle: "ios",
      cleanup_started_at: stale_cutoff,
      lease_expires_at: stale_lease,
      updated_at: stale_cutoff
    }

    {:ok, cleanup_agent} = Agent.start_link(fn -> stale_cleanup end)

    stub(Repo, :insert, fn %ProjectCleanup{} = struct, _opts ->
      Agent.get_and_update(cleanup_agent, fn %ProjectCleanup{lease_expires_at: current_lease} = existing ->
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

    assert %ProjectCleanup{cleanup_started_at: persisted_cutoff, lease_expires_at: persisted_lease} =
             Agent.get(cleanup_agent, & &1)

    assert persisted_cutoff == fresh_cutoff
    assert DateTime.after?(persisted_lease, fresh_cutoff)
  end

  test "renew_project_cleanup_lease extends the active lease for the same cleanup" do
    cutoff = DateTime.utc_now()

    expect(Repo, :update_all, fn _query, updates ->
      [set: set_values] = updates
      assert DateTime.after?(set_values[:lease_expires_at], cutoff)
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
end
