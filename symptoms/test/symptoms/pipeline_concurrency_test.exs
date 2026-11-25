defmodule Symptoms.PipelineConcurrencyTest do
  # Two pipeline jobs of the same length must never process windows at the
  # same time. Each job needs its own database connection for that, so this
  # test runs outside the sandbox (`unboxed_run`) and truncates afterwards;
  # it is synchronous, so no sandboxed test runs alongside it.
  use Symptoms.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Symptoms.FakeSource
  alias Symptoms.Pipeline
  alias Symptoms.Store

  @t0 ~U[2026-11-16 10:00:00.000000Z]
  @route %{service: "tuist-server", kind: "route", key: "POST /api/runs"}

  setup do
    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        tables =
          Repo.query!("SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename <> 'schema_migrations'").rows
          |> List.flatten()
          |> Enum.map_join(", ", &~s("#{&1}"))

        Repo.query!("TRUNCATE #{tables} RESTART IDENTITY CASCADE")
      end)
    end)

    Sandbox.unboxed_run(Repo, fn ->
      FakeSource.seed_history([@route], @t0)
      # The last finished window is t0 − 1 min, so a job at t0 + 5 min 30 s
      # processes t0 … t0 + 3 min: latest = ⌊(t0 + 5:30 − 60 s) / 60⌋ · 60 − 60.
      Repo.insert_all(Store.PipelineRun, [
        %{
          window_seconds: 60,
          window_start: DateTime.shift(@t0, minute: -1),
          records: 0,
          entities: 0,
          finished_at: @t0
        }
      ])
    end)

    :ok
  end

  # One job: the first window's collect reports to the test and waits for
  # `:go`, so the test can start the second job while the first is inside a
  # window.
  defp job(test) do
    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Process.put(:fake_source, &collect(&1, test))

        try do
          Pipeline.run_pending(60, DateTime.shift(@t0, minute: 5, second: 30), sources: [FakeSource])
        rescue
          error -> {:raised, Exception.message(error)}
        end
      end)
    end)
  end

  defp collect(window, test) do
    if window.start == DateTime.to_unix(@t0) do
      send(test, {:entered, self()})
      receive do: (:go -> :ok)
    end

    {:ok, FakeSource.records(window, [@route], 100)}
  end

  test "a job longer than the query timeout keeps its lock and opens one symptom" do
    first = job(self())
    assert_receive {:entered, first_pid}, 5_000

    # A source request may take 30 seconds. The pipeline's session must
    # survive the repository's default 15-second query timeout, including
    # while no SQL is running, or another job can process the same window.
    Process.sleep(16_000)

    second = job(self())

    # Without mutual exclusion the second job enters the same window too.
    receive do
      {:entered, second_pid} -> send(second_pid, :go)
    after
      1_000 -> :ok
    end

    send(first_pid, :go)
    results = Enum.map([first, second], &Task.await(&1, 30_000))

    # Pipeline test hand calculation: the 4th loud window (t0 + 3 min)
    # crosses h = 6 (4 · 1.906 = 7.62), so exactly one symptom and one
    # `opened` revision; every window is processed once.
    Sandbox.unboxed_run(Repo, fn ->
      assert Repo.aggregate(Store.Symptom, :count) == 1

      assert Repo.aggregate(
               from(r in Store.Revision, where: fragment("?->>'transition'", r.document) == "opened"),
               :count
             ) == 1

      duplicates =
        Repo.all(
          from(r in Store.RootScore,
            group_by: [r.root_key, r.window_seconds, r.window_start],
            having: count() > 1,
            select: r.root_key
          )
        )

      assert duplicates == []
    end)

    assert Enum.sort(results) == [:locked, :ok]
  end
end
