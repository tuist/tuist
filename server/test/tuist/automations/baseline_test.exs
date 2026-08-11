defmodule Tuist.Automations.BaselineTest do
  use TuistTestSupport.Cases.DataCase, async: true

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
end
