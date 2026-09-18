defmodule Tuist.Kura.Workers.AwaitActivationWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Kura
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Reconciler
  alias Tuist.Kura.Server
  alias Tuist.Kura.Workers.AwaitActivationWorker
  alias Tuist.Repo

  setup :set_mimic_from_context

  setup do
    stub(Tuist.Environment, :kura_control_plane?, fn -> true end)
    %{server: %Server{id: UUIDv7.generate()}}
  end

  test "checks twice a second within a run, then snoozes, while the instance is coming up", %{server: server} do
    # A snooze alone runs the job again only after Oban's stager and fetch,
    # 2.5 to 3 seconds later on staging, so each run checks on its own clock.
    expect(Reconciler, :activate_when_ready, 14, fn id ->
      assert id == server.id
      {:waiting, %Deployment{inserted_at: DateTime.utc_now()}}
    end)

    assert {:snooze, 0} = perform_job(AwaitActivationWorker, %{"server_id" => server.id})
  end

  test "snoozes on its clock when checks are slow, rather than running past Oban's shutdown grace",
       %{server: server} do
    # A gateway that accepts TCP and never completes the handshake costs a
    # check the `/up` probe's whole timeout. Counting checks alone would let a
    # run overrun the grace period and be killed mid-check by a deploy, which
    # leaves the job `:executing` and its server without a fast path.
    {:ok, checks} = Agent.start_link(fn -> 0 end)

    stub(Reconciler, :activate_when_ready, fn id ->
      assert id == server.id
      Agent.update(checks, &(&1 + 1))
      Process.sleep(200)
      {:waiting, %Deployment{inserted_at: DateTime.utc_now()}}
    end)

    assert {:snooze, 0} = perform_job(AwaitActivationWorker, %{"server_id" => server.id})
    assert Agent.get(checks, & &1) < 14
  end

  test "enqueues again for a server whose earlier run was killed mid-check", %{server: server} do
    {:ok, first} = AwaitActivationWorker.enqueue(server)

    # What a deploy killing a run past the grace period leaves behind.
    # `Oban.Plugins.Lifeline` only rescues it after 30 minutes, so an unbounded
    # unique period would hold the fast path off this server for that long.
    first
    |> Ecto.Changeset.change(
      state: "executing",
      inserted_at: DateTime.add(DateTime.utc_now(), -61, :second)
    )
    |> Repo.update!()

    assert {:ok, second} = AwaitActivationWorker.enqueue(server)
    assert second.id != first.id
  end

  test "stops within the run as soon as the instance activates", %{server: server} do
    expect(Reconciler, :activate_when_ready, 1, fn _id -> {:waiting, %Deployment{inserted_at: DateTime.utc_now()}} end)
    expect(Reconciler, :activate_when_ready, 1, fn _id -> :done end)

    assert :ok = perform_job(AwaitActivationWorker, %{"server_id" => server.id})
  end

  test "stops once the instance is active", %{server: server} do
    expect(Reconciler, :activate_when_ready, fn id ->
      assert id == server.id
      :done
    end)

    assert :ok = perform_job(AwaitActivationWorker, %{"server_id" => server.id})
  end

  test "leaves an attempt that has stalled to the reconciler tick", %{server: server} do
    started_at = DateTime.add(DateTime.utc_now(), -Kura.provisioning_stall_seconds() - 1, :second)

    expect(Reconciler, :activate_when_ready, fn id ->
      assert id == server.id
      {:waiting, %Deployment{inserted_at: started_at}}
    end)

    assert :ok = perform_job(AwaitActivationWorker, %{"server_id" => server.id})
  end

  test "does nothing when this process is not the Kura control plane", %{server: server} do
    stub(Tuist.Environment, :kura_control_plane?, fn -> false end)
    reject(&Reconciler.activate_when_ready/1)

    assert :ok = perform_job(AwaitActivationWorker, %{"server_id" => server.id})
  end
end
