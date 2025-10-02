defmodule TuistWeb.Webhooks.GitHubControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.AppBuilds
  alias Tuist.GitHubAppInstallations
  alias Tuist.Projects
  alias Tuist.QA
  alias Tuist.Repo
  alias Tuist.VCS
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.GitHubAppInstallationsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Webhooks.GitHubController

  describe "handle/2" do
    test "returns ok for unknown event types", %{conn: conn} do
      # Given
      conn = put_req_header(conn, "x-github-event", "push")

      # When
      result = GitHubController.handle(conn, %{})

      # Then
      assert result.status == 200
    end

    test "returns ok for non-created actions", %{conn: conn} do
      # Given
      conn = put_req_header(conn, "x-github-event", "issue_comment")

      # When
      result =
        GitHubController.handle(conn, %{
          "action" => "edited",
          "comment" => %{"body" => "/tuist qa some prompt"},
          "repository" => %{"full_name" => "org/repo"},
          "issue" => %{"number" => 42, "pull_request" => %{}}
        })

      # Then
      assert result.status == 200
    end

    test "returns ok for comments without pull_request", %{conn: conn} do
      # Given
      conn = put_req_header(conn, "x-github-event", "issue_comment")

      # When
      result =
        GitHubController.handle(conn, %{
          "action" => "created",
          "comment" => %{"body" => "/tuist qa some prompt"},
          "repository" => %{"full_name" => "org/repo"},
          "issue" => %{"number" => 42}
        })

      # Then
      assert result.status == 200
    end

    test "ignores comments without QA prompt", %{conn: conn} do
      # Given
      conn = put_req_header(conn, "x-github-event", "issue_comment")

      reject(Projects, :project_by_vcs_repository_full_handle, 2)

      # When
      result =
        GitHubController.handle(conn, %{
          "action" => "created",
          "comment" => %{"body" => "Just a regular comment"},
          "repository" => %{"full_name" => "org/repo"},
          "issue" => %{"number" => 42, "pull_request" => %{}}
        })

      # Then
      assert result.status == 200
    end

    test "handles project not found gracefully", %{conn: conn} do
      # Given
      conn = put_req_header(conn, "x-github-event", "issue_comment")

      expect(Projects, :project_by_vcs_repository_full_handle, fn "org/repo", _ ->
        {:error, :not_found}
      end)

      # When
      result =
        GitHubController.handle(conn, %{
          "action" => "created",
          "comment" => %{"body" => "/tuist qa test the app"},
          "repository" => %{"full_name" => "org/repo"},
          "issue" => %{"number" => 42, "pull_request" => %{}}
        })

      # Then
      assert result.status == 200
    end

    test "posts message when QA feature flag is disabled for account", %{conn: conn} do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Repo.get_by!(Account, organization_id: organization.id)

      ProjectsFixtures.project_fixture(
        account_id: account.id,
        vcs_connection: [
          repository_full_handle: "org/repo",
          provider: :github
        ]
      )

      conn = put_req_header(conn, "x-github-event", "issue_comment")

      expect(FunWithFlags, :enabled?, fn :qa, [for: ^account] ->
        false
      end)

      expect(VCS, :create_comment, fn comment_params ->
        assert comment_params.body ==
                 "Tuist QA is currently not generally available. Contact us at contact@tuist.dev if you'd like an early preview of the feature."

        {:ok, %{"id" => "comment_123"}}
      end)

      # When
      result =
        GitHubController.handle(conn, %{
          "action" => "created",
          "comment" => %{"body" => "/tuist qa test login flow"},
          "repository" => %{"full_name" => "org/repo"},
          "issue" => %{"number" => 42, "pull_request" => %{}}
        })

      # Then
      assert result.status == 200
    end

    test "creates QA worker job when app build exists and feature flag is enabled", %{conn: conn} do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Repo.get_by!(Account, organization_id: organization.id)

      project =
        ProjectsFixtures.project_fixture(
          account_id: account.id,
          vcs_connection: [
            repository_full_handle: "org/repo",
            provider: :github
          ]
        )

      preview = AppBuildsFixtures.preview_fixture(project: project)
      app_build = AppBuildsFixtures.app_build_fixture(preview: preview)

      conn = put_req_header(conn, "x-github-event", "issue_comment")

      expect(FunWithFlags, :enabled?, fn :qa, [for: ^account] ->
        true
      end)

      expect(AppBuilds, :latest_app_build, fn "refs/pull/42/merge", ^project, _opts ->
        app_build
      end)

      qa_run_fixture = %QA.Run{
        id: "qa-run-id",
        app_build_id: app_build.id,
        prompt: "test login flow",
        status: "pending",
        git_ref: "refs/pull/42/merge",
        issue_comment_id: nil
      }

      updated_qa_run_fixture = %{qa_run_fixture | issue_comment_id: "comment_123"}

      expect(QA, :create_qa_run, fn _params ->
        {:ok, qa_run_fixture}
      end)

      expect(VCS, :create_comment, fn _comment_params ->
        {:ok, %{"id" => "comment_123"}}
      end)

      expect(QA, :update_qa_run, fn ^qa_run_fixture, %{issue_comment_id: "comment_123"} ->
        {:ok, updated_qa_run_fixture}
      end)

      expect(QA, :enqueue_test_worker, fn qa_run ->
        assert qa_run.app_build_id == app_build.id
        assert qa_run.prompt == "test login flow"
        assert qa_run.issue_comment_id == "comment_123"

        {:ok, %Oban.Job{}}
      end)

      # When
      result =
        GitHubController.handle(conn, %{
          "action" => "created",
          "comment" => %{"body" => "/tuist qa test login flow"},
          "repository" => %{"full_name" => "org/repo"},
          "issue" => %{"number" => 42, "pull_request" => %{}}
        })

      # Then
      assert result.status == 200
    end

    test "creates pending QA run when no app build exists and feature flag is enabled", %{conn: conn} do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Repo.get_by!(Account, organization_id: organization.id)

      project =
        ProjectsFixtures.project_fixture(
          account_id: account.id,
          vcs_connection: [
            repository_full_handle: "org/repo",
            provider: :github
          ]
        )

      conn = put_req_header(conn, "x-github-event", "issue_comment")

      expect(Projects, :project_by_vcs_repository_full_handle, fn "org/repo", _ ->
        {:ok, project}
      end)

      expect(FunWithFlags, :enabled?, fn :qa, [for: ^account] ->
        true
      end)

      expect(AppBuilds, :latest_app_build, fn "refs/pull/55/merge", ^project, _opts ->
        nil
      end)

      expect(VCS, :create_comment, fn _comment_params ->
        {:ok, %{"id" => "comment_789"}}
      end)

      # When
      result =
        GitHubController.handle(conn, %{
          "action" => "created",
          "comment" => %{"body" => "/tuist qa test performance"},
          "repository" => %{"full_name" => "org/repo"},
          "issue" => %{"number" => 55, "pull_request" => %{}}
        })

      # Then
      assert result.status == 200
    end

    test "ignores QA prompt in quoted text with > prefix", %{conn: conn} do
      # Given
      conn = put_req_header(conn, "x-github-event", "issue_comment")

      reject(Projects, :project_by_vcs_repository_full_handle, 2)

      # When
      result =
        GitHubController.handle(conn, %{
          "action" => "created",
          "comment" => %{
            "body" => "> /tuist qa test the app\nThis should not trigger"
          },
          "repository" => %{"full_name" => "org/repo"},
          "issue" => %{"number" => 42, "pull_request" => %{}}
        })

      # Then
      assert result.status == 200
    end

    test "handles installation deleted event successfully", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account
      installation_id = "12345"

      github_app_installation =
        GitHubAppInstallationsFixtures.github_app_installation_fixture(
          account_id: account.id,
          installation_id: installation_id
        )

      conn = put_req_header(conn, "x-github-event", "installation")

      expect(GitHubAppInstallations, :get_by_installation_id, fn ^installation_id ->
        {:ok, github_app_installation}
      end)

      expect(GitHubAppInstallations, :delete, fn ^github_app_installation ->
        {:ok, github_app_installation}
      end)

      # When
      result =
        GitHubController.handle(conn, %{
          "action" => "deleted",
          "installation" => %{"id" => installation_id}
        })

      # Then
      assert result.status == 200
    end

    test "handles installation created event successfully", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account
      installation_id = "67890"
      html_url = "https://github.com/organizations/tuist/settings/installations/67890"

      github_app_installation =
        GitHubAppInstallationsFixtures.github_app_installation_fixture(
          account_id: account.id,
          installation_id: installation_id
        )

      conn = put_req_header(conn, "x-github-event", "installation")

      expect(GitHubAppInstallations, :get_by_installation_id, fn ^installation_id ->
        {:ok, github_app_installation}
      end)

      expect(GitHubAppInstallations, :update, fn ^github_app_installation, %{html_url: ^html_url} ->
        {:ok, %{github_app_installation | html_url: html_url}}
      end)

      # When
      result =
        GitHubController.handle(conn, %{
          "action" => "created",
          "installation" => %{"id" => installation_id, "html_url" => html_url}
        })

      # Then
      assert result.status == 200
    end

    test "returns ok for installation events with non-deleted actions", %{conn: conn} do
      # Given
      conn = put_req_header(conn, "x-github-event", "installation")

      # When
      result =
        GitHubController.handle(conn, %{
          "action" => "suspend",
          "installation" => %{"id" => "12345"}
        })

      # Then
      assert result.status == 200
    end
  end
end
