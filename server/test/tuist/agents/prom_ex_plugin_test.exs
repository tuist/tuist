defmodule Tuist.Agents.PromExPluginTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Agents.Lease
  alias Tuist.Agents.PromExPlugin

  setup do
    test_pid = self()
    handler = "agents-waiting-#{System.unique_integer()}"

    :telemetry.attach(
      handler,
      [:prom_ex, :plugin, :tuist, :agents, :sessions, :waiting],
      fn _event, measurements, _meta, _ -> send(test_pid, {:waiting, measurements}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  # Only sessions a pod could claim now are waiting: not one a pod holds, nor
  # one delayed after a failure, nor one that is no longer wanted.
  test "reports the sessions no pod holds that want one now, and how long the oldest waited" do
    [waiting, held, delayed, idle] = for _ <- 1..4, do: "s-" <> Ecto.UUID.generate()
    Enum.each([waiting, held, delayed, idle], &Lease.want(&1, "thread"))

    epochs = Map.new(Lease.claim("host", 100), &{&1.id, &1.epoch})
    :ok = Lease.release(waiting, epochs[waiting])
    :ok = Lease.release(delayed, epochs[delayed], delay_ms: 60_000)
    :ok = Lease.release(idle, epochs[idle], wanted: false)

    Repo.update_all(from(s in "agent_sessions", where: s.id == ^waiting),
      set: [wanted_at: DateTime.add(DateTime.utc_now(), -120)]
    )

    PromExPlugin.execute_session_metrics()

    assert_receive {:waiting, %{count: 1, age_seconds: age}}
    assert age >= 119 and age < 600
    assert Map.has_key?(epochs, held)
  end

  test "reports zero when nothing waits" do
    PromExPlugin.execute_session_metrics()
    assert_receive {:waiting, %{count: 0, age_seconds: +0.0}}
  end
end
