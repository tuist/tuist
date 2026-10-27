defmodule Tuist.Automations.Actions.SendSlackActionTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Automations.Actions.SendSlackAction
  alias Tuist.Automations.Workers.SlackNotificationWorker
  alias Tuist.Projects
  alias Tuist.Slack
  alias Tuist.Slack.Client
  alias Tuist.Tests
  alias TuistTestSupport.Fixtures.AutomationsFixtures

  test "persists an interpolated message without performing Slack HTTP" do
    alert = AutomationsFixtures.automation_alert_fixture(name: "Quarantine")
    id = Ecto.UUID.generate()
    {:ok, encrypted} = Slack.encrypt_webhook_url("https://hooks.slack.com/services/test")

    action = %{
      "type" => "send_slack",
      "channel" => "C123",
      "webhook_url_encrypted" => encrypted,
      "message" => "Test {{test_case.name}} in {{test_case.module_name}} matched {{automation.name}}"
    }

    expect(Tests, :get_test_case_by_id, fn ^id ->
      {:ok, %{id: id, name: "test<&>", module_name: "Module", suite_name: "Suite", project_id: alert.project_id}}
    end)

    reject(&Client.post_to_webhook/2)
    reject(&Client.deliver_once/2)
    assert :ok = SendSlackAction.execute(alert, %{type: :test_case, id: id}, action)
    assert [job] = all_enqueued(worker: SlackNotificationWorker)
    assert job.args["alert_id"] == alert.id
    assert job.args["action"] == action
    assert Enum.any?(job.args["blocks"], &(get_in(&1, ["text", "text"]) == ":robot_face: Quarantine"))

    assert Enum.any?(
             job.args["blocks"],
             &(get_in(&1, ["text", "text"]) == "Test test&lt;&amp;&gt; in Module matched Quarantine")
           )

    refute JSON.encode!(job.args) =~ "https://hooks.slack.com"
  end

  test "does not enqueue when the test case is missing" do
    alert = AutomationsFixtures.automation_alert_fixture()
    expect(Tests, :get_test_case_by_id, fn _ -> {:error, :not_found} end)
    assert :ok = SendSlackAction.execute(alert, %{type: :test_case, id: Ecto.UUID.generate()}, %{})
    assert all_enqueued(worker: SlackNotificationWorker) == []
  end

  test "does not enqueue when the project is missing" do
    alert = AutomationsFixtures.automation_alert_fixture()
    expect(Tests, :get_test_case_by_id, fn _ -> {:ok, %{}} end)
    expect(Projects, :get_project_by_id, fn _ -> nil end)
    assert :ok = SendSlackAction.execute(alert, %{type: :test_case, id: Ecto.UUID.generate()}, %{})
    assert all_enqueued(worker: SlackNotificationWorker) == []
  end
end
