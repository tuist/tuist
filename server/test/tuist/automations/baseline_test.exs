defmodule Tuist.Automations.BaselineTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Ecto.Query

  alias Tuist.Automations
  alias Tuist.Automations.Alerts.BaselineAttempt
  alias Tuist.Automations.Alerts.BaselineResult
  alias Tuist.Automations.Alerts.Event, as: AlertEvent
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Repo
  alias Tuist.Tests.TestCase
  alias TuistTestSupport.Fixtures.AutomationsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "captures one cursor before bounded evaluation and commits the complete baseline" do
    project = ProjectsFixtures.project_fixture()
    alert = AutomationsFixtures.automation_alert_fixture(project: project, baseline_established_at: nil)
    test_process = self()
    now = NaiveDateTime.utc_now()

    test_case_ids =
      Enum.map(1..2001, fn index ->
        id = Ecto.UUID.generate()

        %{
          id: id,
          name: "test#{index}",
          module_name: "Tests",
          suite_name: "Baseline",
          project_id: project.id,
          last_status: "success",
          last_duration: 1,
          last_ran_at: now,
          inserted_at: now,
          recent_durations: [1],
          avg_duration: 1
        }
      end)

    IngestRepo.insert_all(TestCase, test_case_ids)

    assert :ok =
             Automations.establish_alert_baseline(alert, fn batch ->
               send(test_process, {:evaluated_batch, length(batch)})
               batch
             end)

    assert_receive {:evaluated_batch, 2000}
    assert_receive {:evaluated_batch, 1}
    refute_receive {:evaluated_batch, _}

    updated_alert = Repo.reload!(alert)
    attempt = Repo.get_by!(BaselineAttempt, alert_id: alert.id, baseline_generation: 0)

    assert attempt.state == "committed"
    assert attempt.cursor == updated_alert.baseline_established_at
    assert attempt.cursor == updated_alert.last_scoped_evaluation_inserted_at
    assert attempt.evaluation_cursor

    assert Repo.aggregate(
             from(result in BaselineResult, where: result.attempt_id == ^attempt.id),
             :count
           ) == 0

    event_count =
      ClickHouseRepo.one(
        from(event in AlertEvent,
          where: event.alert_id == ^alert.id,
          select: count()
        )
      )

    assert event_count == 2001
  end

  test "resumes evaluation from the last persisted keyset page" do
    project = ProjectsFixtures.project_fixture()
    alert = AutomationsFixtures.automation_alert_fixture(project: project, baseline_established_at: nil)
    now = NaiveDateTime.utc_now()

    test_cases =
      Enum.map(1..2001, fn index ->
        %{
          id: Ecto.UUID.generate(),
          name: "test#{index}",
          module_name: "Tests",
          suite_name: "InterruptedBaseline",
          project_id: project.id,
          last_status: "success",
          last_duration: 1,
          last_ran_at: now,
          inserted_at: now,
          recent_durations: [1],
          avg_duration: 1
        }
      end)

    IngestRepo.insert_all(TestCase, test_cases)

    assert_raise RuntimeError, "interrupted", fn ->
      Automations.establish_alert_baseline(alert, fn test_case_ids ->
        if length(test_case_ids) == 1, do: raise("interrupted")
        test_case_ids
      end)
    end

    attempt = Repo.get_by!(BaselineAttempt, alert_id: alert.id, baseline_generation: 0)

    assert attempt.state == "evaluating"
    assert attempt.evaluation_cursor

    assert Repo.aggregate(
             from(result in BaselineResult, where: result.attempt_id == ^attempt.id),
             :count
           ) == 2000

    test_process = self()

    assert :ok =
             Automations.establish_alert_baseline(alert, fn test_case_ids ->
               send(test_process, {:resumed_batch_size, length(test_case_ids)})
               test_case_ids
             end)

    assert_receive {:resumed_batch_size, 1}
    refute_receive {:resumed_batch_size, _}
    assert Repo.reload!(attempt).state == "committed"

    assert 2001 ==
             ClickHouseRepo.one(
               from(event in AlertEvent,
                 where: event.alert_id == ^alert.id,
                 select: count()
               )
             )
  end

  test "resumes the same attempt and hides events from an older monitor definition" do
    alert = AutomationsFixtures.automation_alert_fixture(baseline_established_at: nil)

    assert {:ok, first_attempt} = Automations.begin_alert_baseline(alert)
    assert {:ok, resumed_attempt} = Automations.begin_alert_baseline(alert)
    assert resumed_attempt.id == first_attempt.id
    assert resumed_attempt.cursor == first_attempt.cursor

    test_case_id = Ecto.UUID.generate()
    now = NaiveDateTime.utc_now()
    event_id = Ecto.UUID.generate()

    event = %{
      id: event_id,
      alert_id: alert.id,
      baseline_generation: 0,
      test_case_id: test_case_id,
      status: "triggered",
      triggered_at: now,
      inserted_at: now
    }

    IngestRepo.insert_all(AlertEvent, [event, event])

    assert [%{test_case_id: ^test_case_id}] = Automations.list_active_alert_events(alert.id)

    assert {:ok, updated_alert} =
             Automations.update_alert(alert, %{
               "trigger_config" => %{
                 "threshold" => 20,
                 "window_type" => "last_days",
                 "window" => "30d"
               }
             })

    assert updated_alert.baseline_generation == 1
    assert updated_alert.baseline_established_at == nil
    assert Automations.list_active_alert_events(alert.id) == []
  end

  test "resumes publication without evaluating the project again" do
    alert = AutomationsFixtures.automation_alert_fixture(baseline_established_at: nil)
    test_case_id = Ecto.UUID.generate()

    assert {:ok, attempt} = Automations.begin_alert_baseline(alert)

    Repo.insert_all(BaselineResult, [
      %{
        attempt_id: attempt.id,
        test_case_id: test_case_id,
        inserted_at: DateTime.utc_now(:second)
      }
    ])

    publishing_attempt =
      attempt
      |> BaselineAttempt.changeset(%{state: "publishing"})
      |> Repo.update!()

    assert :ok =
             Automations.establish_alert_baseline(alert, fn _batch ->
               flunk("a publishing retry must not evaluate the project again")
             end)

    assert Repo.reload!(publishing_attempt).state == "committed"
    assert [%{test_case_id: ^test_case_id}] = Automations.list_active_alert_events(alert.id)

    assert :ok =
             Automations.establish_alert_baseline(alert, fn _batch ->
               flunk("a committed baseline must not evaluate the project again")
             end)

    assert 1 ==
             ClickHouseRepo.one(
               from(event in AlertEvent,
                 where: event.alert_id == ^alert.id,
                 select: count()
               )
             )
  end

  test "applies existing matches once and resumes after the last completed action" do
    alert = AutomationsFixtures.automation_alert_fixture(baseline_established_at: nil)
    [first, second] = Enum.sort([Ecto.UUID.generate(), Ecto.UUID.generate()])
    attempt = publishing_attempt(alert, [first, second])
    test_process = self()

    assert_raise RuntimeError, "simulated interruption", fn ->
      Automations.establish_alert_baseline(alert, & &1, fn _alert, id ->
        if id == first do
          send(test_process, {:applied, id})
          :ok
        else
          raise "simulated interruption"
        end
      end)
    end

    assert_receive {:applied, ^first}
    assert Repo.reload!(attempt).last_published_test_case_id == first
    assert Repo.reload!(alert).baseline_established_at == nil

    assert :ok =
             Automations.establish_alert_baseline(alert, & &1, fn _alert, id ->
               send(test_process, {:applied, id})
               :ok
             end)

    assert_receive {:applied, ^second}
    refute_receive {:applied, ^first}
    assert Repo.reload!(attempt).state == "committed"
    assert Enum.sort(Enum.map(Automations.list_active_alert_events(alert.id), & &1.test_case_id)) == [first, second]

    assert :ok =
             Automations.establish_alert_baseline(alert, fn _ -> flunk("already evaluated") end, fn _, _ ->
               flunk("already applied")
             end)
  end

  test "a returned action error does not block other matches or baseline completion" do
    alert = AutomationsFixtures.automation_alert_fixture(baseline_established_at: nil)
    [first, second] = Enum.sort([Ecto.UUID.generate(), Ecto.UUID.generate()])
    attempt = publishing_attempt(alert, [first, second])

    assert :ok =
             Automations.establish_alert_baseline(alert, & &1, fn _, id ->
               if id == first, do: {:error, :channel_not_found}, else: :ok
             end)

    assert Repo.reload!(attempt).state == "committed"
    assert Repo.reload!(alert).baseline_established_at
    assert [%{test_case_id: ^second}] = Automations.list_active_alert_events(alert.id)
  end

  test "new requests and cancellations preserve recovery events and invalidate stale attempts" do
    alert = AutomationsFixtures.automation_alert_fixture(baseline_established_at: nil)
    recovering = Ecto.UUID.generate()
    publishing_attempt(alert, [recovering])
    assert :ok = Automations.establish_alert_baseline(alert, & &1)
    assert [original_event] = Automations.list_active_alert_events(alert.id)
    alert = Repo.reload!(alert)

    config = Map.put(alert.trigger_config, "apply_actions_to_existing_matches", true)
    assert {:ok, requested} = Automations.update_alert(alert, %{trigger_config: config})
    pending = publishing_attempt(requested, [Ecto.UUID.generate()])
    assert [^original_event] = Automations.list_active_alert_events(requested)

    assert {:ok, cancelled} =
             Automations.update_alert(requested, %{
               trigger_config: Map.put(config, "apply_actions_to_existing_matches", false)
             })

    refute cancelled.trigger_config["apply_actions_to_existing_matches"]
    assert cancelled.baseline_generation > pending.baseline_generation
    assert [^original_event] = Automations.list_active_alert_events(cancelled.id)
    assert :ok = Automations.establish_alert_baseline(requested, & &1, fn _, _ -> flunk("cancelled action") end)

    # A silent replacement must not restart an existing recovery dwell window.
    publishing_attempt(cancelled, [recovering])
    assert :ok = Automations.establish_alert_baseline(cancelled, & &1)
    assert [^original_event] = Automations.list_active_alert_events(cancelled.id)

    assert {:ok, changed} =
             Automations.update_alert(Repo.reload!(cancelled), %{
               trigger_config: Map.put(alert.trigger_config, "threshold", 20)
             })

    assert Automations.list_active_alert_events(changed) == []
    assert changed.event_generation == changed.baseline_generation
  end

  test "silent retries deduplicate identical payloads but accept a changed active event set" do
    alert = AutomationsFixtures.automation_alert_fixture(baseline_established_at: nil)
    [first, second] = Enum.sort([Ecto.UUID.generate(), Ecto.UUID.generate()])
    attempt = publishing_attempt(alert, [first, second])
    test_pid = self()

    for _ <- 1..2 do
      expect(ClickHouseRepo, :all, fn _query, _opts -> [%{test_case_id: first}] end)

      expect(IngestRepo, :insert_all, fn AlertEvent, records, opts ->
        send(test_pid, {:publication, Enum.map(records, & &1.test_case_id), opts[:settings][:insert_deduplication_token]})
        raise "unknown insert outcome"
      end)

      assert_raise RuntimeError, "unknown insert outcome", fn ->
        Automations.establish_alert_baseline(alert, & &1)
      end
    end

    assert_receive {:publication, [^second], first_token}
    assert_receive {:publication, [^second], ^first_token}
    assert Repo.reload!(attempt).last_published_test_case_id == nil

    expect(ClickHouseRepo, :all, fn _query, _opts -> [] end)

    expect(IngestRepo, :insert_all, fn AlertEvent, records, opts ->
      assert Enum.map(records, & &1.test_case_id) == [first, second]
      refute opts[:settings][:insert_deduplication_token] == first_token
      {length(records), nil}
    end)

    assert :ok = Automations.establish_alert_baseline(alert, & &1)
    assert Repo.reload!(attempt).state == "committed"
  end

  test "actioned baseline events start recovery dwell when actions run" do
    alert = AutomationsFixtures.automation_alert_fixture(baseline_established_at: nil)
    id = Ecto.UUID.generate()
    attempt = publishing_attempt(alert, [id])
    old_cursor = DateTime.add(DateTime.utc_now(:second), -3600, :second)
    attempt |> BaselineAttempt.changeset(%{cursor: old_cursor}) |> Repo.update!()
    before_actions = NaiveDateTime.utc_now()

    assert :ok = Automations.establish_alert_baseline(alert, & &1, fn _, ^id -> :ok end)
    assert [%{triggered_at: triggered_at}] = Automations.list_active_alert_events(alert.id)
    assert NaiveDateTime.compare(triggered_at, before_actions) in [:eq, :gt]
  end

  test "rechecks saved matches before publication and leaves changed tests untriggered" do
    alert = AutomationsFixtures.automation_alert_fixture(baseline_established_at: nil)
    [matching, changed] = [Ecto.UUID.generate(), Ecto.UUID.generate()]
    publishing_attempt(alert, [matching, changed])
    test_process = self()

    assert :ok =
             Automations.establish_alert_baseline(
               alert,
               fn ids ->
                 assert Enum.sort(ids) == Enum.sort([matching, changed])
                 [matching]
               end,
               fn _alert, id ->
                 send(test_process, {:applied, id})
                 :ok
               end
             )

    assert_receive {:applied, ^matching}
    refute_receive {:applied, ^changed}
    assert [%{test_case_id: ^matching}] = Automations.list_active_alert_events(alert.id)
  end

  test "a stale worker cannot start the current generation using its old condition" do
    alert = AutomationsFixtures.automation_alert_fixture(baseline_established_at: nil)
    {:ok, updated} = Automations.update_alert(alert, %{trigger_config: Map.put(alert.trigger_config, "threshold", 20)})

    assert :ok =
             Automations.establish_alert_baseline(alert, fn _ -> flunk("stale condition") end, fn _, _ ->
               flunk("stale actions")
             end)

    assert Repo.get_by(BaselineAttempt, alert_id: alert.id, baseline_generation: updated.baseline_generation) == nil
    assert Repo.reload!(updated).baseline_established_at == nil
  end

  test "an edit during publication prevents the old baseline from applying actions" do
    alert = AutomationsFixtures.automation_alert_fixture(baseline_established_at: nil)
    id = Ecto.UUID.generate()
    publishing_attempt(alert, [id])

    assert :ok =
             Automations.establish_alert_baseline(
               alert,
               fn ids ->
                 {:ok, _} =
                   Automations.update_alert(alert, %{trigger_config: Map.put(alert.trigger_config, "threshold", 20)})

                 ids
               end,
               fn _, _ -> flunk("stale baseline must not apply actions") end
             )

    assert Repo.reload!(alert).baseline_generation == 1
    assert Automations.list_active_alert_events(alert.id) == []
  end

  test "a disabled alert pauses publication until it is enabled again" do
    alert = AutomationsFixtures.automation_alert_fixture(baseline_established_at: nil)
    id = Ecto.UUID.generate()
    attempt = publishing_attempt(alert, [id])
    {:ok, _} = Automations.update_alert(alert, %{enabled: false})
    assert :ok = Automations.establish_alert_baseline(alert, & &1, fn _, _ -> flunk("disabled alert") end)
    assert Repo.reload!(attempt).last_published_test_case_id == nil

    {:ok, enabled} = Automations.update_alert(alert, %{enabled: true})
    assert :ok = Automations.establish_alert_baseline(enabled, & &1, fn _, ^id -> :ok end)
    assert Repo.reload!(attempt).state == "committed"
  end

  test "leaves publication to the next run when a competing worker still owns the enumeration" do
    project = ProjectsFixtures.project_fixture()
    alert = AutomationsFixtures.automation_alert_fixture(project: project, baseline_established_at: nil)
    {:ok, attempt} = Automations.begin_alert_baseline(alert)
    late_id = Ecto.UUID.generate()

    # A second evaluation job advances the shared attempt's keyset cursor while
    # this one is reading its page, so the page this worker sees is already
    # empty. The competing worker has not yet written the results for that page.
    expect(ClickHouseRepo, :all, fn _query, _opts ->
      attempt
      |> BaselineAttempt.changeset(%{
        evaluation_cursor: %{"module_name" => "Tests", "suite_name" => "Baseline", "name" => "z", "id" => late_id}
      })
      |> Repo.update!()

      []
    end)

    assert :ok = Automations.establish_alert_baseline(alert, & &1)

    reloaded = Repo.reload!(attempt)
    assert reloaded.state == "evaluating"
    assert reloaded.last_published_test_case_id == nil
    assert is_nil(Repo.reload!(alert).baseline_established_at)
    assert Automations.list_active_alert_events(alert.id) == []
  end

  test "discards the superseded attempt's results when a save advances the generation" do
    alert = AutomationsFixtures.automation_alert_fixture(baseline_established_at: nil)
    attempt = publishing_attempt(alert, [Ecto.UUID.generate(), Ecto.UUID.generate()])

    assert Repo.aggregate(where(BaselineResult, attempt_id: ^attempt.id), :count) == 2

    config = Map.put(alert.trigger_config, "apply_actions_to_existing_matches", true)
    assert {:ok, requested} = Automations.update_alert(alert, %{trigger_config: config})

    assert requested.baseline_generation > attempt.baseline_generation
    assert Repo.aggregate(where(BaselineResult, attempt_id: ^attempt.id), :count) == 0
  end

  defp publishing_attempt(alert, test_case_ids) do
    {:ok, attempt} = Automations.begin_alert_baseline(alert)

    Repo.insert_all(
      BaselineResult,
      Enum.map(test_case_ids, fn id ->
        %{attempt_id: attempt.id, test_case_id: id, inserted_at: DateTime.utc_now(:second)}
      end)
    )

    attempt |> BaselineAttempt.changeset(%{state: "publishing"}) |> Repo.update!()
  end
end
