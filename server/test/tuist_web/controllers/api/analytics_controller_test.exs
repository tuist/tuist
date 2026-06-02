defmodule TuistWeb.API.AnalyticsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Tests
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  describe "GET /api/projects/:account_handle/:project_handle/runs/job-summary" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "renders the run report markdown for a merge queue ref", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      git_ref = "refs/heads/gh-readonly-queue/main/pr-1-abc123"

      {:ok, test_run} =
        Tests.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          git_ref: git_ref,
          git_commit_sha: "1234567890",
          status: "success",
          scheme: "App",
          duration: 0,
          macos_version: "11.2.3",
          xcode_version: "12.4",
          is_ci: true,
          ran_at: ~N[2024-04-30 03:00:00],
          test_modules: []
        })

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/runs/job-summary?git_ref=#{git_ref}"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["markdown"] =~ "### 🛠️ Tuist Run Report 🛠️"
      assert response["markdown"] =~ "#### Tests 🧪"
      assert response["markdown"] =~ test_run.id
    end

    test "returns null markdown when there is nothing to report", %{
      conn: conn,
      user: user,
      project: project
    } do
      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/runs/job-summary?git_ref=refs/heads/gh-readonly-queue/main/pr-2-def456"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["markdown"] == nil
    end

    test "returns unauthorized without authentication", %{user: user, project: project} do
      # When
      conn =
        get(
          build_conn(),
          "/api/projects/#{user.account.name}/#{project.name}/runs/job-summary?git_ref=refs/heads/main"
        )

      # Then
      assert json_response(conn, :unauthorized)
    end
  end
end
