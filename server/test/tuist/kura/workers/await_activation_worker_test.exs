defmodule Tuist.Kura.Workers.AwaitActivationWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Kura
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Reconciler
  alias Tuist.Kura.Server
  alias Tuist.Kura.Workers.AwaitActivationWorker

  setup :set_mimic_from_context

  setup do
    stub(Tuist.Environment, :kura_control_plane?, fn -> true end)
    %{server: %Server{id: UUIDv7.generate()}}
  end

  test "checks every second within a run, then snoozes, while the instance is coming up", %{server: server} do
    # A snooze alone runs the job again only after Oban's stager and fetch,
    # 2.5 to 3 seconds later on staging, so each run checks on its own clock.
    expect(Reconciler, :activate_when_ready, 13, fn id ->
      assert id == server.id
      {:waiting, %Deployment{inserted_at: DateTime.utc_now()}}
    end)

    assert {:snooze, 0} = perform_job(AwaitActivationWorker, %{"server_id" => server.id})
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
