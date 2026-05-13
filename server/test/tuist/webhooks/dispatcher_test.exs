defmodule Tuist.Webhooks.DispatcherTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.IngestRepo
  alias Tuist.Tests.TestCase
  alias Tuist.Webhooks
  alias Tuist.Webhooks.Dispatcher
  alias Tuist.Webhooks.Workers.DeliveryWorker
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  defp insert_test_case(project, attrs \\ []) do
    test_case = RunsFixtures.test_case_fixture([project_id: project.id] ++ attrs)
    IngestRepo.insert_all(TestCase, [test_case |> Map.from_struct() |> Map.delete(:__meta__)])
    test_case
  end

  describe "dispatch_test_case_event/3" do
    test "enqueues a DeliveryWorker job per matching endpoint" do
      project = ProjectsFixtures.project_fixture()

      {:ok, subscribed, _} =
        Webhooks.create_endpoint(project.account_id, %{
          "name" => "Jira",
          "url" => "https://example.com/hook",
          "event_types" => ["test_case.updated"]
        })

      test_case = insert_test_case(project, is_flaky: true, state: "muted")

      assert :ok = Dispatcher.dispatch_test_case_event(test_case, [:marked_flaky, :muted])

      [job] = Tuist.Repo.all(Oban.Job)
      assert job.worker == inspect(DeliveryWorker)
      assert job.args["webhook_endpoint_id"] == subscribed.id
      assert job.args["event_type"] == "test_case.updated"

      payload = job.args["payload"]
      assert payload["type"] == "test_case.updated"
      assert payload["events"] == ["marked_flaky", "muted"]
      assert payload["object"]["id"] == test_case.id
      assert payload["object"]["is_flaky"] == true
      assert payload["object"]["state"] == "muted"
      assert payload["endpoint"]["id"] == subscribed.id
      assert payload["account"]["id"] == project.account_id
    end

    test "skips endpoints in other accounts" do
      project = ProjectsFixtures.project_fixture()
      other_project = ProjectsFixtures.project_fixture()

      {:ok, _other_endpoint, _} =
        Webhooks.create_endpoint(other_project.account_id, %{
          "name" => "Other",
          "url" => "https://example.com/other",
          "event_types" => ["test_case.updated"]
        })

      test_case = insert_test_case(project)

      assert :ok = Dispatcher.dispatch_test_case_event(test_case, [:marked_flaky])
      assert Tuist.Repo.aggregate(Oban.Job, :count) == 0
    end

    test "no-ops when no endpoints are subscribed" do
      project = ProjectsFixtures.project_fixture()
      test_case = insert_test_case(project)

      assert :ok = Dispatcher.dispatch_test_case_event(test_case, [:marked_flaky])
      assert Tuist.Repo.aggregate(Oban.Job, :count) == 0
    end

    test "forwards actor_id and alert_id when supplied" do
      project = ProjectsFixtures.project_fixture()

      {:ok, _endpoint, _} =
        Webhooks.create_endpoint(project.account_id, %{
          "name" => "Hook",
          "url" => "https://example.com/hook",
          "event_types" => ["test_case.updated"]
        })

      test_case = insert_test_case(project)
      alert_id = Ecto.UUID.generate()

      assert :ok =
               Dispatcher.dispatch_test_case_event(test_case, [:muted],
                 actor_id: 42,
                 alert_id: alert_id
               )

      [job] = Tuist.Repo.all(Oban.Job)
      assert job.args["payload"]["actor_id"] == 42
      assert job.args["payload"]["alert_id"] == alert_id
    end
  end
end
