defmodule Atlas.Engineering.Alerts.Workers.EvaluateSpikesTest do
  use Atlas.DataCase, async: true
  use Mimic

  import Oban.Testing, only: [all_enqueued: 1]

  alias Atlas.Engineering.Alerts
  alias Atlas.Engineering.Alerts.Rule
  alias Atlas.Engineering.Alerts.Workers.DeliverRule
  alias Atlas.Engineering.Alerts.Workers.EvaluateSpikes
  alias Atlas.Engineering.Errors
  alias Atlas.Engineering.Projects
  alias Ecto.Adapters.SQL.Sandbox

  test "minute evaluation queues each enabled rule/issue once and leaves disabled rules alone" do
    {:ok, project} = Projects.create_project(%{name: "spikes-#{System.unique_integer([:positive])}"})

    attrs = %{
      name: "Production spike",
      trigger: :event_spike,
      threshold_event_count: 100,
      threshold_window_minutes: 5,
      environment: "prod",
      min_level: :error,
      slack_channel_id: "test-channel"
    }

    {:ok, enabled} = Alerts.create_rule(project, attrs)
    {:ok, _disabled} = Alerts.create_rule(project, Map.put(attrs, :enabled, false))
    issue_ids = [Ecto.UUID.generate(), Ecto.UUID.generate()]
    stub(Errors, :enabled?, fn -> true end)

    stub(Alerts, :spike_matches, fn rule, _at ->
      assert rule.id == enabled.id
      {:ok, Enum.map(issue_ids, &%{issue_id: &1, event_count: 107})}
    end)

    assert :ok = EvaluateSpikes.perform(%Oban.Job{})
    assert :ok = EvaluateSpikes.perform(%Oban.Job{})
    jobs = all_enqueued(repo: Repo, worker: DeliverRule)
    assert length(jobs) == 2
    assert Enum.sort(Enum.map(jobs, & &1.args["subject_id"])) == Enum.sort(issue_ids)
    assert Enum.all?(jobs, &(&1.args["rule_id"] == enabled.id and &1.args["environment"] == "prod"))

    {:ok, _other} = Alerts.create_rule(project, Map.put(attrs, :name, "Another production spike"))
    other_issue_id = Ecto.UUID.generate()
    stub(Alerts, :spike_matches, fn _, _ -> {:ok, [%{issue_id: other_issue_id, event_count: 107}]} end)
    expect(Alerts, :spike_matches, fn _, _ -> {:error, :spike_query_failed} end)

    assert {:error, :spike_query_failed} = EvaluateSpikes.perform(%Oban.Job{})
    jobs = all_enqueued(repo: Repo, worker: DeliverRule)
    assert length(jobs) == 3
    assert Enum.any?(jobs, &(&1.args["subject_id"] == other_issue_id))
  end

  test "completed evaluations and old orphaned executions cannot suppress the next minute" do
    stub(Errors, :enabled?, fn -> false end)
    Oban.insert!(EvaluateSpikes.new(%{}))
    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :default, with_safety: false)

    next = Oban.insert!(EvaluateSpikes.new(%{}))
    refute next.conflict?

    duplicate = Oban.insert!(EvaluateSpikes.new(%{}))
    assert duplicate.conflict?
    assert duplicate.id == next.id

    Repo.update_all(from(job in Oban.Job, where: job.id == ^next.id),
      set: [state: "executing", inserted_at: DateTime.add(DateTime.utc_now(), -120, :second)]
    )

    refute Oban.insert!(EvaluateSpikes.new(%{})).conflict?
  end

  test "only one replica evaluates at once and losing its connection releases the lock" do
    parent = self()
    stub(Errors, :enabled?, fn -> true end)
    stub(Repo, :all, fn _query -> [%Rule{}] end)

    stub(Alerts, :spike_matches, fn _, _ ->
      send(parent, {:evaluating, self()})

      receive do
        :finish -> {:ok, []}
      after
        10_000 -> flunk("evaluation was not released")
      end
    end)

    first = Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> EvaluateSpikes.perform(%Oban.Job{}) end) end)
    first_pid = first.pid
    assert_receive {:evaluating, ^first_pid}, 10_000

    second = Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> EvaluateSpikes.perform(%Oban.Job{}) end) end)
    second_pid = second.pid
    assert :ok = Task.await(second, 10_000)
    refute_receive {:evaluating, ^second_pid}

    Process.unlink(first_pid)
    Process.exit(first_pid, :kill)
    assert_receive {:DOWN, _, :process, ^first_pid, :killed}, 10_000

    # Worker DOWN can precede PostgreSQL rolling back its disconnected session.
    # Wait for that real cleanup without sleeping before testing the next run.
    cleanup =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.transaction(fn ->
            Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", ["atlas.alert.spike_evaluation"])
          end)
        end)
      end)

    assert {:ok, _} = Task.await(cleanup, 10_000)

    retry = Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> EvaluateSpikes.perform(%Oban.Job{}) end) end)
    retry_pid = retry.pid
    assert_receive {:evaluating, ^retry_pid}, 10_000
    send(retry_pid, :finish)
    assert :ok = Task.await(retry, 10_000)
  end
end
