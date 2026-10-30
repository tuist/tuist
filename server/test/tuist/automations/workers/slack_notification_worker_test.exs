defmodule Tuist.Automations.Workers.SlackNotificationWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Automations
  alias Tuist.Automations.Workers.SlackNotificationWorker
  alias Tuist.Slack
  alias Tuist.Slack.Client
  alias TuistTestSupport.Fixtures.AutomationsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.SlackFixtures

  setup do
    action = %{"type" => "send_slack", "channel" => "C123", "message" => "A test matched"}
    %{action: action}
  end

  test "decrypts webhooks only when delivering and honors Retry-After", %{action: action} do
    url = "https://hooks.slack.com/services/test"
    {:ok, encrypted} = Slack.encrypt_webhook_url(url)
    action = Map.put(action, "webhook_url_encrypted", encrypted)
    alert = AutomationsFixtures.automation_alert_fixture(trigger_actions: [action])
    expect(Client, :deliver_once, fn {:webhook, ^url}, [] -> {:snooze, 42} end)
    assert {:snooze, 42} = SlackNotificationWorker.perform(job(alert, action))
  end

  test "uses current bot credentials for legacy channel actions", %{action: action} do
    project = ProjectsFixtures.project_fixture()
    installation = SlackFixtures.slack_installation_fixture(account_id: project.account_id)
    alert = AutomationsFixtures.automation_alert_fixture(project: project, trigger_actions: [action])

    expect(Client, :deliver_once, fn {:channel, token, "C123"}, [] ->
      assert token == installation.access_token
      :ok
    end)

    assert :ok = SlackNotificationWorker.perform(job(alert, action))
  end

  test "transient transport failures remain retryable", %{action: action} do
    {:ok, encrypted} = Slack.encrypt_webhook_url("https://hooks.slack.com/services/test")
    action = Map.put(action, "webhook_url_encrypted", encrypted)
    alert = AutomationsFixtures.automation_alert_fixture(trigger_actions: [action])
    expect(Client, :deliver_once, fn _, _ -> {:error, :slack_transport_error} end)
    assert {:error, :slack_transport_error} = SlackNotificationWorker.perform(job(alert, action))
  end

  test "invalid credentials are discarded without HTTP", %{action: action} do
    action = Map.put(action, "webhook_url_encrypted", "invalid")
    alert = AutomationsFixtures.automation_alert_fixture(trigger_actions: [action])
    reject(&Client.deliver_once/2)
    assert {:discard, :invalid_webhook} = SlackNotificationWorker.perform(job(alert, action))
  end

  test "disabled, deleted, and edited alerts cancel queued notifications", %{action: action} do
    alert = AutomationsFixtures.automation_alert_fixture(trigger_actions: [action])
    reject(&Client.deliver_once/2)
    {:ok, _} = Automations.update_alert(alert, %{enabled: false})
    assert :ok = SlackNotificationWorker.perform(job(alert, action))

    {:ok, alert} =
      Automations.update_alert(alert, %{enabled: true, trigger_actions: [Map.put(action, "message", "Updated")]})

    assert :ok = SlackNotificationWorker.perform(job(alert, action))
    Repo.delete!(alert)
    assert :ok = SlackNotificationWorker.perform(job(alert, action))
  end

  defp job(alert, action), do: %Oban.Job{args: %{"alert_id" => alert.id, "action" => action, "blocks" => []}}
end
