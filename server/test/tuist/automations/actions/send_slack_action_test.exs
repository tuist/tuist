defmodule Tuist.Automations.Actions.SendSlackActionTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Automations.Actions.SendSlackAction
  alias Tuist.Projects
  alias Tuist.Slack.Client
  alias Tuist.Slack.Installation
  alias Tuist.Tests
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.SlackFixtures

  defp setup_project(_) do
    %{account: account} = AccountsFixtures.user_fixture(preload: [:account])
    SlackFixtures.slack_installation_fixture(account_id: account.id)
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
    test "posts a message with interpolated variables to the configured channel", %{project: project} do
      automation = %{name: "Quarantine", project_id: project.id}
      tc = test_case(project.id)

      expect(Tests, :get_test_case_by_id, fn _id -> {:ok, tc} end)

      expect(Client, :post_message, fn access_token, channel, blocks ->
        assert is_binary(access_token)
        assert channel == "C123"
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
        "message" => "Test {{test_case.name}} in {{test_case.module_name}} matched {{automation.name}}"
      }

      assert :ok = SendSlackAction.execute(automation, tc.id, action)
    end

    test "uses default message when template is empty", %{project: project} do
      automation = %{name: "Auto", project_id: project.id}
      tc = test_case(project.id)

      expect(Tests, :get_test_case_by_id, fn _id -> {:ok, tc} end)

      expect(Client, :post_message, fn _token, _channel, blocks ->
        message =
          Enum.find_value(blocks, fn block ->
            case block do
              %{type: "section", text: %{text: text}} -> text
              _ -> nil
            end
          end)

        assert message =~ "Auto"
        assert message =~ tc.name
        :ok
      end)

      action = %{"type" => "send_slack", "channel" => "C1", "message" => ""}
      assert :ok = SendSlackAction.execute(automation, tc.id, action)
    end

    test "no-ops when the project is not found" do
      automation = %{name: "Auto", project_id: 999_999}

      expect(Tests, :get_test_case_by_id, fn _id ->
        {:ok, %{id: Ecto.UUID.generate(), name: "x", module_name: "y", suite_name: "z", project_id: 999_999}}
      end)

      expect(Projects, :get_project_by_id, fn _id -> nil end)

      reject(&Client.post_message/3)

      assert :ok =
               SendSlackAction.execute(
                 automation,
                 Ecto.UUID.generate(),
                 %{"type" => "send_slack", "channel" => "C1", "message" => "hi"}
               )
    end

    test "no-ops when the project has no Slack installation" do
      project = ProjectsFixtures.project_fixture()
      automation = %{name: "Auto", project_id: project.id}
      tc = test_case(project.id)

      expect(Tests, :get_test_case_by_id, fn _id -> {:ok, tc} end)
      reject(&Client.post_message/3)

      assert :ok =
               SendSlackAction.execute(
                 automation,
                 tc.id,
                 %{"type" => "send_slack", "channel" => "C1", "message" => "hi"}
               )
    end

    test "no-ops when the test case is not found" do
      _project = %{}
      automation = %{name: "Auto", project_id: 1}

      expect(Tests, :get_test_case_by_id, fn _id -> {:error, :not_found} end)
      reject(&Client.post_message/3)

      assert :ok =
               SendSlackAction.execute(
                 automation,
                 Ecto.UUID.generate(),
                 %{"type" => "send_slack", "channel" => "C1", "message" => "hi"}
               )
    end

    # Suppress unused alias warnings when the helpers above don't reference all aliases in every test.
    test "Installation alias is referenced", _ctx do
      assert Installation.__schema__(:source) == "slack_installations"
    end
  end
end
