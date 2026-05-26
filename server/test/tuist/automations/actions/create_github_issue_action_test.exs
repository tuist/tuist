defmodule Tuist.Automations.Actions.CreateGithubIssueActionTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Automations
  alias Tuist.Automations.Actions.CreateGithubIssueAction
  alias Tuist.GitHub.Client
  alias Tuist.Tests
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AutomationsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  defp test_case(project_id) do
    %{
      id: Ecto.UUID.generate(),
      name: "testFoo",
      module_name: "MyModule",
      suite_name: "MySuite",
      project_id: project_id
    }
  end

  defp connected_project do
    user = AccountsFixtures.user_fixture()

    ProjectsFixtures.project_fixture(
      account: user.account,
      vcs_connection: [repository_full_handle: "tuist/tuist"]
    )
  end

  describe "execute/3" do
    test "creates a GitHub issue and records the IssueLink" do
      project = connected_project()
      alert = AutomationsFixtures.automation_alert_fixture(project: project)
      tc = test_case(project.id)

      expect(Tests, :get_test_case_by_id, fn _id -> {:ok, tc} end)

      expect(Client, :create_issue, fn %{
                                         repository_full_handle: "tuist/tuist",
                                         title: title,
                                         body: body,
                                         labels: ["flaky"]
                                       } ->
        assert title == "Flaky: testFoo"
        assert body =~ "MyModule"
        {:ok, %{"number" => 42, "node_id" => "I_node", "html_url" => "https://github.com/tuist/tuist/issues/42"}}
      end)

      action = %{
        "type" => "create_github_issue",
        "title_template" => "Flaky: {{test_case.name}}",
        "body_template" => "Module {{test_case.module_name}}",
        "labels" => ["flaky"]
      }

      assert :ok =
               CreateGithubIssueAction.execute(alert, %{type: :test_case, id: tc.id}, action)

      link = Automations.get_open_issue_link(alert.id, tc.id)
      assert link
      assert link.github_issue_number == 42
      assert link.github_repository_full_handle == "tuist/tuist"
      assert link.state == "open"
    end

    test "is idempotent when an open IssueLink already exists" do
      project = connected_project()
      alert = AutomationsFixtures.automation_alert_fixture(project: project)
      tc = test_case(project.id)

      project = Tuist.Repo.preload(project, vcs_connection: :github_app_installation)

      {:ok, _existing} =
        Automations.create_issue_link(%{
          project_id: project.id,
          alert_id: alert.id,
          test_case_id: tc.id,
          github_app_installation_id: project.vcs_connection.github_app_installation_id,
          github_repository_full_handle: "tuist/tuist",
          github_issue_number: 7,
          opened_at: DateTime.truncate(DateTime.utc_now(), :second)
        })

      expect(Tests, :get_test_case_by_id, fn _id -> {:ok, tc} end)
      reject(&Client.create_issue/1)

      action = %{
        "type" => "create_github_issue",
        "title_template" => "Flaky: {{test_case.name}}"
      }

      assert :ok =
               CreateGithubIssueAction.execute(alert, %{type: :test_case, id: tc.id}, action)
    end

    test "skips when the project has no GitHub connection" do
      project = ProjectsFixtures.project_fixture()
      alert = AutomationsFixtures.automation_alert_fixture(project: project)
      tc = test_case(project.id)

      expect(Tests, :get_test_case_by_id, fn _id -> {:ok, tc} end)
      reject(&Client.create_issue/1)

      action = %{
        "type" => "create_github_issue",
        "title_template" => "Flaky: {{test_case.name}}"
      }

      assert :ok =
               CreateGithubIssueAction.execute(alert, %{type: :test_case, id: tc.id}, action)
    end

    test "skips when the test case is not found" do
      project = connected_project()
      alert = AutomationsFixtures.automation_alert_fixture(project: project)

      expect(Tests, :get_test_case_by_id, fn _id -> {:error, :not_found} end)
      reject(&Client.create_issue/1)

      action = %{
        "type" => "create_github_issue",
        "title_template" => "Flaky: {{test_case.name}}"
      }

      assert :ok =
               CreateGithubIssueAction.execute(
                 alert,
                 %{type: :test_case, id: Ecto.UUID.generate()},
                 action
               )
    end

    test "returns an error when the GitHub API call fails" do
      project = connected_project()
      alert = AutomationsFixtures.automation_alert_fixture(project: project)
      tc = test_case(project.id)

      expect(Tests, :get_test_case_by_id, fn _id -> {:ok, tc} end)
      expect(Client, :create_issue, fn _ -> {:error, "boom"} end)

      action = %{
        "type" => "create_github_issue",
        "title_template" => "Flaky: {{test_case.name}}"
      }

      assert {:error, "boom"} =
               CreateGithubIssueAction.execute(alert, %{type: :test_case, id: tc.id}, action)

      assert Automations.get_open_issue_link(alert.id, tc.id) == nil
    end
  end
end
