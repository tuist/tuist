defmodule Tuist.Automations.Actions.SendWebhookActionTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Automations.Actions.SendWebhookAction
  alias Tuist.IngestRepo
  alias Tuist.Tests.TestCase
  alias Tuist.Webhooks
  alias Tuist.Webhooks.Workers.DeliveryWorker
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  defp insert_test_case(attrs) do
    project = ProjectsFixtures.project_fixture()
    test_case = RunsFixtures.test_case_fixture([project_id: project.id] ++ attrs)
    IngestRepo.insert_all(TestCase, [test_case |> Map.from_struct() |> Map.delete(:__meta__)])
    test_case
  end

  defp automation, do: %{id: Ecto.UUID.generate(), name: "Mark flaky → Jira", project_id: 1}

  defp valid_action(extras \\ %{}) do
    %{plaintext: _, encrypted: encrypted} = Webhooks.generate_signing_secret()

    Map.merge(
      %{"type" => "send_webhook", "url" => "https://example.com/hook", "signing_secret_encrypted" => encrypted},
      extras
    )
  end

  test "enqueues a DeliveryWorker job with the envelope payload" do
    test_case = insert_test_case(is_flaky: true, state: "muted")
    action = valid_action()
    automation = automation()

    assert :ok = SendWebhookAction.execute(automation, %{type: :test_case, id: test_case.id}, action)

    [job] = Tuist.Repo.all(Oban.Job)
    assert job.worker == inspect(DeliveryWorker)
    assert job.args["url"] == action["url"]
    assert job.args["signing_secret_encrypted"] == action["signing_secret_encrypted"]
    assert job.args["event_type"] == "test_case.updated"

    payload = job.args["payload"]
    assert payload["type"] == "test_case.updated"
    assert payload["object"]["id"] == test_case.id
    assert payload["object"]["is_flaky"] == true
    assert payload["object"]["state"] == "muted"
    assert payload["automation"]["id"] == automation.id
    assert payload["automation"]["name"] == automation.name
  end

  test "skips silently when the test case can't be found" do
    automation = automation()
    action = valid_action()

    assert :ok =
             SendWebhookAction.execute(
               automation,
               %{type: :test_case, id: Ecto.UUID.generate()},
               action
             )

    assert Tuist.Repo.aggregate(Oban.Job, :count) == 0
  end

  test "skips silently when the action is missing url or signing secret" do
    test_case = insert_test_case([])
    automation = automation()

    assert :ok =
             SendWebhookAction.execute(
               automation,
               %{type: :test_case, id: test_case.id},
               %{"type" => "send_webhook", "url" => "", "signing_secret_encrypted" => ""}
             )

    assert Tuist.Repo.aggregate(Oban.Job, :count) == 0
  end
end
