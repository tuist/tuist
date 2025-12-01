defmodule TuistWeb.Webhooks.GitHubControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.AppBuilds
  alias Tuist.Projects
  alias Tuist.QA
  alias Tuist.Repo
  alias Tuist.VCS
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.VCSFixtures
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

      reject(Projects, :projects_by_vcs_repository_full_handle, 2)

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

    test "creates pending QA run when no app build exists and feature flag is enabled", %{
      conn: conn
    } do
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
        VCSFixtures.github_app_installation_fixture(
          account_id: account.id,
          installation_id: installation_id
        )

      conn = put_req_header(conn, "x-github-event", "installation")

      expect(VCS, :get_github_app_installation_by_installation_id, fn ^installation_id ->
        {:ok, github_app_installation}
      end)

      expect(VCS, :delete_github_app_installation, fn ^github_app_installation ->
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

    test "handles installation deleted event when installation not found", %{conn: conn} do
      # Given
      installation_id = "99999"
      conn = put_req_header(conn, "x-github-event", "installation")

      expect(VCS, :get_github_app_installation_by_installation_id, fn ^installation_id ->
        {:error, :not_found}
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
        VCSFixtures.github_app_installation_fixture(
          account_id: account.id,
          installation_id: installation_id
        )

      conn = put_req_header(conn, "x-github-event", "installation")

      expect(VCS, :get_github_app_installation_by_installation_id, fn ^installation_id ->
        {:ok, github_app_installation}
      end)

      expect(VCS, :update_github_app_installation, fn ^github_app_installation, %{html_url: ^html_url} ->
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

    test "handles installation created event when installation not found after retries",
         %{
           conn: conn
         } do
      # Given
      installation_id = "88888"
      html_url = "https://github.com/organizations/tuist/settings/installations/88888"
      conn = put_req_header(conn, "x-github-event", "installation")

      # Expect 3 attempts (original + 2 retries)
      expect(VCS, :get_github_app_installation_by_installation_id, 3, fn ^installation_id ->
        {:error, :not_found}
      end)

      # When
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          result =
            GitHubController.handle(conn, %{
              "action" => "created",
              "installation" => %{"id" => installation_id, "html_url" => html_url}
            })

          # Then
          assert result.status == 200
        end)

      # Verify final error was logged after all retries exhausted
      assert log =~ "installation_id=#{installation_id}"
      assert log =~ "not found after retries"
    end

    test "handles installation created event with successful retry",
         %{
           conn: conn
         } do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account
      installation_id = "99999"
      html_url = "https://github.com/organizations/tuist/settings/installations/99999"

      github_app_installation =
        VCSFixtures.github_app_installation_fixture(
          account_id: account.id,
          installation_id: installation_id
        )

      conn = put_req_header(conn, "x-github-event", "installation")

      # Simulate race condition: first call returns not found, but installation
      # is created by the time of the retry
      call_count = :counters.new(1, [])

      expect(VCS, :get_github_app_installation_by_installation_id, 2, fn ^installation_id ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count == 0 do
          {:error, :not_found}
        else
          {:ok, github_app_installation}
        end
      end)

      expect(VCS, :update_github_app_installation, fn ^github_app_installation, %{html_url: ^html_url} ->
        {:ok, %{github_app_installation | html_url: html_url}}
      end)

      # When
      result =
        GitHubController.handle(conn, %{
          "action" => "created",
          "installation" => %{"id" => installation_id, "html_url" => html_url}
        })

      # Then - successfully handled after retry
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

    test "handles QA prompt with explicit project name", %{conn: conn} do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Repo.get_by!(Account, organization_id: organization.id)

      ProjectsFixtures.project_fixture(
        name: "mobile-app",
        account_id: account.id,
        vcs_connection: [
          repository_full_handle: "org/monorepo",
          provider: :github
        ]
      )

      conn = put_req_header(conn, "x-github-event", "issue_comment")

      expect(FunWithFlags, :enabled?, fn :qa, [for: ^account] ->
        true
      end)

      expect(VCS, :create_comment, fn _comment_params ->
        {:ok, %{"id" => "comment_123"}}
      end)

      expect(QA, :create_qa_run, fn _params ->
        {:ok, %QA.Run{id: "qa-run-id", issue_comment_id: nil}}
      end)

      expect(QA, :update_qa_run, fn _, _ ->
        {:ok, %QA.Run{id: "qa-run-id", issue_comment_id: "comment_123"}}
      end)

      # When
      result =
        GitHubController.handle(conn, %{
          "action" => "created",
          "comment" => %{"body" => "/tuist mobile-app qa test login flow"},
          "repository" => %{"full_name" => "org/monorepo"},
          "issue" => %{"number" => 42, "pull_request" => %{}}
        })

      # Then
      assert result.status == 200
    end

    test "posts error message when project not found with explicit name", %{conn: conn} do
      # Given
      conn = put_req_header(conn, "x-github-event", "issue_comment")

      expect(Projects, :project_by_name_and_vcs_repository_full_handle, fn "nonexistent", "org/monorepo", _ ->
        {:error, :not_found}
      end)

      expect(VCS, :create_comment, fn comment_params ->
        assert comment_params.body == "Project 'nonexistent' is not connected to this repository."
        assert comment_params.project == nil
        {:ok, %{"id" => "comment_456"}}
      end)

      # When
      result =
        GitHubController.handle(conn, %{
          "action" => "created",
          "comment" => %{"body" => "/tuist nonexistent qa test something"},
          "repository" => %{"full_name" => "org/monorepo"},
          "issue" => %{"number" => 42, "pull_request" => %{}}
        })

      # Then
      assert result.status == 200
    end

    test "requires project name when multiple projects in monorepo", %{conn: conn} do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Repo.get_by!(Account, organization_id: organization.id)

      _project_one =
        ProjectsFixtures.project_fixture(
          name: "mobile-app",
          account_id: account.id,
          vcs_connection: [
            repository_full_handle: "org/monorepo",
            provider: :github
          ]
        )

      _project_two =
        ProjectsFixtures.project_fixture(
          name: "admin-panel",
          account_id: account.id,
          vcs_connection: [
            repository_full_handle: "org/monorepo",
            provider: :github
          ]
        )

      conn = put_req_header(conn, "x-github-event", "issue_comment")

      expect(VCS, :create_comment, fn comment_params ->
        expected_message =
          "Multiple Tuist projects are connected to this repository. Please specify the project handle: `/tuist <project-handle> qa <your-prompt>`\n\nAvailable projects: mobile-app, admin-panel"

        assert comment_params.body == expected_message
        {:ok, %{"id" => "comment_789"}}
      end)

      # When
      result =
        GitHubController.handle(conn, %{
          "action" => "created",
          "comment" => %{"body" => "/tuist qa test everything"},
          "repository" => %{"full_name" => "org/monorepo"},
          "issue" => %{"number" => 42, "pull_request" => %{}}
        })

      # Then
      assert result.status == 200
    end

    test "handles multiple projects connected to same repository with deterministic comment creation",
         %{conn: conn} do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Repo.get_by!(Account, organization_id: organization.id)

      # Create two projects connected to the same GitHub repository (monorepo scenario)
      _project_one =
        ProjectsFixtures.project_fixture(
          name: "project-one",
          account_id: account.id,
          vcs_connection: [
            repository_full_handle: "company/monorepo",
            provider: :github
          ]
        )

      _project_two =
        ProjectsFixtures.project_fixture(
          name: "project-two",
          account_id: account.id,
          vcs_connection: [
            repository_full_handle: "company/monorepo",
            provider: :github
          ]
        )

      conn = put_req_header(conn, "x-github-event", "issue_comment")

      expect(VCS, :create_comment, fn comment_params ->
        expected_message =
          "Multiple Tuist projects are connected to this repository. Please specify the project handle: `/tuist <project-handle> qa <your-prompt>`\n\nAvailable projects: project-one, project-two"

        assert comment_params.body == expected_message
        assert comment_params.repository_full_handle == "company/monorepo"
        assert comment_params.git_ref == "refs/pull/123/merge"
        {:ok, %{"id" => "comment_multiple_projects"}}
      end)

      # When
      result =
        GitHubController.handle(conn, %{
          "action" => "created",
          "comment" => %{"body" => "/tuist qa test user authentication"},
          "repository" => %{"full_name" => "company/monorepo"},
          "issue" => %{"number" => 123, "pull_request" => %{}}
        })

      # Then
      assert result.status == 200
    end

    test "successfully processes QA prompt with specified project in monorepo", %{conn: conn} do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Repo.get_by!(Account, organization_id: organization.id)

      # Create two projects connected to the same GitHub repository (monorepo scenario)
      _project_one =
        ProjectsFixtures.project_fixture(
          name: "project-one",
          account_id: account.id,
          vcs_connection: [
            repository_full_handle: "company/monorepo",
            provider: :github
          ]
        )

      project_two =
        ProjectsFixtures.project_fixture(
          name: "project-two",
          account_id: account.id,
          vcs_connection: [
            repository_full_handle: "company/monorepo",
            provider: :github
          ]
        )

      conn = put_req_header(conn, "x-github-event", "issue_comment")

      expect(FunWithFlags, :enabled?, fn :qa, [for: ^account] ->
        true
      end)

      expect(VCS, :create_comment, fn comment_params ->
        assert comment_params.body =~ "No preview found for your PR"
        assert comment_params.repository_full_handle == "company/monorepo"
        assert comment_params.git_ref == "refs/pull/456/merge"
        assert comment_params.project == project_two
        {:ok, %{"id" => "comment_project_two"}}
      end)

      expect(QA, :create_qa_run, fn params ->
        assert params.prompt == "test checkout flow"
        assert params.git_ref == "refs/pull/456/merge"
        assert params.status == "pending"
        assert params.app_build_id == nil
        {:ok, %QA.Run{id: "qa-run-project-two", issue_comment_id: nil}}
      end)

      expect(QA, :update_qa_run, fn _, %{issue_comment_id: "comment_project_two"} ->
        {:ok, %QA.Run{id: "qa-run-project-two", issue_comment_id: "comment_project_two"}}
      end)

      # When
      result =
        GitHubController.handle(conn, %{
          "action" => "created",
          "comment" => %{"body" => "/tuist project-two qa test checkout flow"},
          "repository" => %{"full_name" => "company/monorepo"},
          "issue" => %{"number" => 456, "pull_request" => %{}}
        })

      # Then
      assert result.status == 200
    end
  end
end
