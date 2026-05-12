defmodule Tuist.Automations.Actions.SendWebhookActionTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Automations.Actions.SendWebhookAction
  alias Tuist.IngestRepo
  alias Tuist.Tests.TestCase
  alias Tuist.Webhooks
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  defp setup_project_and_endpoint(_) do
    project = ProjectsFixtures.project_fixture()

    {:ok, endpoint, _} =
      Webhooks.create_endpoint(project.account_id, %{
        "name" => "Jira",
        "url" => "https://example.com/hook"
      })

    %{project: project, endpoint: endpoint}
  end

  defp insert_test_case(project, attrs) do
    test_case = RunsFixtures.test_case_fixture([project_id: project.id] ++ attrs)
    IngestRepo.insert_all(TestCase, [test_case |> Map.from_struct() |> Map.delete(:__meta__)])
    test_case
  end

  defp automation(project), do: %{id: Ecto.UUID.generate(), name: "Auto", project_id: project.id}

  describe "execute/3" do
    setup [:setup_project_and_endpoint]

    test "enqueues a DeliveryWorker job referencing the endpoint id", %{project: project, endpoint: endpoint} do
      test_case = insert_test_case(project, is_flaky: true, state: "muted")
      automation = automation(project)

      assert :ok =
               SendWebhookAction.execute(
                 automation,
                 %{type: :test_case, id: test_case.id},
                 %{"type" => "send_webhook", "webhook_endpoint_id" => endpoint.id}
               )

      [job] = Tuist.Repo.all(Oban.Job)
      assert job.args["webhook_endpoint_id"] == endpoint.id
      assert job.args["event_type"] == "test_case.updated"

      payload = job.args["payload"]
      assert payload["endpoint"]["id"] == endpoint.id
      assert payload["endpoint"]["name"] == endpoint.name
      assert payload["automation"]["id"] == automation.id
      assert payload["object"]["id"] == test_case.id
      assert payload["object"]["is_flaky"] == true
      assert payload["object"]["state"] == "muted"
    end

    test "skips silently when the action is missing webhook_endpoint_id", %{project: project} do
      test_case = insert_test_case(project, [])
      automation = automation(project)

      assert :ok =
               SendWebhookAction.execute(
                 automation,
                 %{type: :test_case, id: test_case.id},
                 %{"type" => "send_webhook"}
               )

      assert Tuist.Repo.aggregate(Oban.Job, :count) == 0
    end

    test "skips silently when the endpoint belongs to a different account", %{project: project} do
      other_project = ProjectsFixtures.project_fixture()

      {:ok, other_endpoint, _} =
        Webhooks.create_endpoint(other_project.account_id, %{
          "name" => "Other",
          "url" => "https://other.example/hook"
        })

      test_case = insert_test_case(project, [])
      automation = automation(project)

      assert :ok =
               SendWebhookAction.execute(
                 automation,
                 %{type: :test_case, id: test_case.id},
                 %{"type" => "send_webhook", "webhook_endpoint_id" => other_endpoint.id}
               )

      assert Tuist.Repo.aggregate(Oban.Job, :count) == 0
    end

    test "skips silently when the endpoint doesn't exist", %{project: project} do
      test_case = insert_test_case(project, [])
      automation = automation(project)

      assert :ok =
               SendWebhookAction.execute(
                 automation,
                 %{type: :test_case, id: test_case.id},
                 %{"type" => "send_webhook", "webhook_endpoint_id" => Ecto.UUID.generate()}
               )

      assert Tuist.Repo.aggregate(Oban.Job, :count) == 0
    end

    test "skips silently when the test case can't be found", %{endpoint: endpoint, project: project} do
      automation = automation(project)

      assert :ok =
               SendWebhookAction.execute(
                 automation,
                 %{type: :test_case, id: Ecto.UUID.generate()},
                 %{"type" => "send_webhook", "webhook_endpoint_id" => endpoint.id}
               )

      assert Tuist.Repo.aggregate(Oban.Job, :count) == 0
    end
  end
end
