defmodule TuistWeb.API.GitHistoryControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias Tuist.GitHistory
  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)
    conn = conn |> Authentication.put_current_user(user) |> put_req_header("content-type", "application/json")
    %{conn: conn, user: user, project: project}
  end

  defp git_history_url(user, project, suffix),
    do: "/api/projects/#{user.account.name}/#{project.name}/tests/git-history#{suffix}"

  test "settings reflect the project's overrides over the defaults", %{conn: conn, user: user, project: project} do
    {:ok, project} = Projects.update_project(project, %{git_history_window_days: 30})

    response = conn |> get(git_history_url(user, project, "/settings")) |> json_response(:ok)

    assert response == %{
             "window_days" => 30,
             "window_commits" => 5000,
             "deepen_budget_seconds" => 60,
             "upload_batch_size" => 500,
             "tracked_file_globs" => GitHistory.default_tracked_file_globs(),
             "tracked_file_limit" => 5000
           }

    {:ok, project} = Projects.update_project(project, %{tracked_file_globs: ["Fixtures/**", "Package.resolved"]})

    assert %{"tracked_file_globs" => ["Fixtures/**", "Package.resolved"]} =
             conn |> get(git_history_url(user, project, "/settings")) |> json_response(:ok)
  end

  test "uploads commits once and reports what is still missing", %{conn: conn, user: user, project: project} do
    body = %{
      object_format: "sha1",
      commits: [
        %{sha: "a", parents: [], committed_at: "2026-09-01T00:00:00Z"},
        %{sha: "b", parents: ["a"], committed_at: "2026-09-01T00:01:00Z"}
      ],
      branch_heads: [%{branch: "main", sha: "b"}]
    }

    assert conn |> post(git_history_url(user, project, "/commits"), body) |> response(:no_content)
    assert conn |> post(git_history_url(user, project, "/commits"), body) |> response(:no_content)

    assert conn
           |> post(git_history_url(user, project, "/commits/missing"), %{shas: ["a", "b", "c"]})
           |> json_response(:ok) ==
             %{"missing" => ["c"]}

    assert GitHistory.ancestors(project.id, "b") == [{"b", 0}, {"a", 1}]
    assert GitHistory.branch_head(project.id, "main") == "b"
  end

  test "refuses a user without access to the project", %{conn: conn, user: user} do
    other = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: other.account.id)

    conn = get(conn, "/api/projects/#{other.account.name}/#{project.name}/tests/git-history/settings")
    assert conn.status in [403, 404]
    refute user.account.id == other.account.id
  end
end
