defmodule Cache.DistributedKV.CleanupTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Cache.DistributedKV.Cleanup
  alias Cache.DistributedKV.Repo, as: DistributedRepo

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

    stub(DistributedRepo, :query!, fn sql, ["acme", "ios", now, lease_expires_at], opts ->
      assert sql =~ "ON CONFLICT"
      assert Keyword.get(opts, :timeout) == Cache.Config.distributed_kv_database_timeout_ms()

      Agent.get_and_update(cleanup_agent, fn state ->
        case state do
          %{cleanup_started_at: cleanup_started_at, lease_expires_at: active_lease} ->
            if DateTime.after?(active_lease, now) do
              {%{rows: [[cleanup_started_at]]}, state}
            else
              next_state = %{cleanup_started_at: now, lease_expires_at: lease_expires_at}
              {%{rows: [[now]]}, next_state}
            end

          _state ->
            next_state = %{cleanup_started_at: now, lease_expires_at: lease_expires_at}
            {%{rows: [[now]]}, next_state}
        end
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

    assert %{cleanup_started_at: persisted_cutoff} = Agent.get(cleanup_agent, & &1)
    assert persisted_cutoff == cutoff_1
  end

  test "expired cleanup leases get a fresh cutoff" do
    stale_cutoff = DateTime.add(DateTime.utc_now(), -120, :second)
    stale_lease = DateTime.add(DateTime.utc_now(), -60, :second)

    {:ok, cleanup_agent} =
      Agent.start_link(fn -> %{cleanup_started_at: stale_cutoff, lease_expires_at: stale_lease} end)

    stub(DistributedRepo, :query!, fn _sql, ["acme", "ios", now, lease_expires_at], _opts ->
      Agent.get_and_update(cleanup_agent, fn %{lease_expires_at: current_lease} = state ->
        if DateTime.after?(current_lease, now) do
          {%{rows: [[state.cleanup_started_at]]}, state}
        else
          next_state = %{cleanup_started_at: now, lease_expires_at: lease_expires_at}
          {%{rows: [[now]]}, next_state}
        end
      end)
    end)

    assert {:ok, fresh_cutoff} = Cleanup.begin_project_cleanup("acme", "ios")
    assert DateTime.after?(fresh_cutoff, stale_cutoff)

    assert %{cleanup_started_at: persisted_cutoff, lease_expires_at: persisted_lease} = Agent.get(cleanup_agent, & &1)
    assert persisted_cutoff == fresh_cutoff
    assert DateTime.after?(persisted_lease, fresh_cutoff)
  end

  test "renew_project_cleanup_lease extends the active lease for the same cleanup" do
    cutoff = DateTime.utc_now()

    expect(DistributedRepo, :query!, fn sql, ["acme", "ios", now, lease_expires_at, ^cutoff], opts ->
      assert sql =~ "UPDATE distributed_kv_project_cleanups"
      assert Keyword.get(opts, :timeout) == Cache.Config.distributed_kv_database_timeout_ms()
      assert DateTime.after?(lease_expires_at, now)
      %{num_rows: 1}
    end)

    assert :ok = Cleanup.renew_project_cleanup_lease("acme", "ios", cutoff)
  end

  test "renew_project_cleanup_lease reports when the lease is no longer active" do
    cutoff = DateTime.utc_now()

    expect(DistributedRepo, :query!, fn _sql, ["acme", "ios", _now, _lease_expires_at, ^cutoff], _opts ->
      %{num_rows: 0}
    end)

    assert {:error, :cleanup_lease_lost} = Cleanup.renew_project_cleanup_lease("acme", "ios", cutoff)
  end
end
