defmodule Tuist.Automations.Actions.SendSlackActionTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Automations.Actions.SendSlackAction
  alias Tuist.Projects
  alias Tuist.Slack
  alias Tuist.Slack.Client
  alias Tuist.Tests
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.SlackFixtures

  defp setup_project(_) do
    %{account: account} = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    %{project: project, account: account}
  end

  setup :setup_project

  defp test_case(project_id) do
    %{
      id: Ecto.UUID.generate(),
      name: "testFoo",
      module_name: "MyModule",
      suite_name: "MySuite",
      project_id: project_id
    }
  end

  describe "execute/3" do
    test "decrypts the webhook URL and posts the message to it", %{project: project} do
      automation = %{name: "Quarantine", project_id: project.id}
      tc = test_case(project.id)
      webhook_url = "https://hooks.slack.com/services/T0/B0/abc"
      {:ok, encrypted} = Slack.encrypt_webhook_url(webhook_url)

      expect(Tests, :get_test_case_by_id, fn _id -> {:ok, tc} end)

      expect(Client, :post_to_webhook, fn url, blocks ->
        assert url == webhook_url

        # The header block should contain the automation name.
        assert Enum.any?(blocks, fn block ->
                 get_in(block, [:text, :text]) == ":robot_face: Quarantine"
               end)

        # Find the message section and verify variable interpolation.
        message =
          Enum.find_value(blocks, fn block ->
            case block do
              %{type: "section", text: %{type: "mrkdwn", text: text}} -> text
              _ -> nil
            end
          end)

        assert message =~ "testFoo"
        assert message =~ "MyModule"
        :ok
      end)

      action = %{
        "type" => "send_slack",
        "channel" => "C123",
        "channel_name" => "general",
        "webhook_url_encrypted" => encrypted,
        "message" => "Test {{test_case.name}} in {{test_case.module_name}} matched {{automation.name}}"
      }

      assert :ok = SendSlackAction.execute(automation, %{type: :test_case, id: tc.id}, action)
    end

    test "falls back to chat.postMessage with the legacy bot token when no encrypted URL is set",
         %{project: project, account: account} do
      installation = SlackFixtures.slack_installation_fixture(account_id: account.id)
      automation = %{name: "Auto", project_id: project.id}
      tc = test_case(project.id)

      expect(Tests, :get_test_case_by_id, fn _id -> {:ok, tc} end)
      reject(&Client.post_to_webhook/2)

      expect(Client, :post_message, fn token, channel, _blocks ->
        assert token == installation.access_token
        assert channel == "C-LEGACY"
        :ok
      end)

      action = %{
        "type" => "send_slack",
        "channel" => "C-LEGACY",
        "webhook_url_encrypted" => "",
        "message" => "hi"
      }

      assert :ok = SendSlackAction.execute(automation, %{type: :test_case, id: tc.id}, action)
    end

    test "no-ops when the project is not found" do
      automation = %{id: Ecto.UUID.generate(), name: "Auto", project_id: 999_999}

      expect(Tests, :get_test_case_by_id, fn _id ->
        {:ok, %{id: Ecto.UUID.generate(), name: "x", module_name: "y", suite_name: "z", project_id: 999_999}}
      end)

      expect(Projects, :get_project_by_id, fn _id -> nil end)

      reject(&Client.post_to_webhook/2)
      reject(&Client.post_message/3)

      assert :ok =
               SendSlackAction.execute(
                 automation,
                 %{type: :test_case, id: Ecto.UUID.generate()},
                 %{"type" => "send_slack", "channel" => "C1", "message" => "hi"}
               )
    end

    test "no-ops when the encrypted URL fails to decrypt", %{project: project} do
      automation = %{id: Ecto.UUID.generate(), name: "Auto", project_id: project.id}
      tc = test_case(project.id)

      expect(Tests, :get_test_case_by_id, fn _id -> {:ok, tc} end)
      reject(&Client.post_to_webhook/2)
      reject(&Client.post_message/3)

      assert :ok =
               SendSlackAction.execute(
                 automation,
                 %{type: :test_case, id: tc.id},
                 %{
                   "type" => "send_slack",
                   "channel" => "C1",
                   "webhook_url_encrypted" => "not-real-ciphertext",
                   "message" => "hi"
                 }
               )
    end

    test "no-ops when the test case is not found" do
      automation = %{id: Ecto.UUID.generate(), name: "Auto", project_id: 1}

      expect(Tests, :get_test_case_by_id, fn _id -> {:error, :not_found} end)
      reject(&Client.post_to_webhook/2)
      reject(&Client.post_message/3)

      assert :ok =
               SendSlackAction.execute(
                 automation,
                 %{type: :test_case, id: Ecto.UUID.generate()},
                 %{"type" => "send_slack", "channel" => "C1", "message" => "hi"}
               )
    end
  end
end
