defmodule TuistWeb.API.GitHistoryControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias Tuist.GitHistory
  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  @remote "https://x-access-token:secret@github.com/Acme/App.git"

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
             "commit_file_limit" => 50_000
           }
  end

  test "uploads commits once into the remote's repository and reports what is still missing", %{
    conn: conn,
    user: user,
    project: project
  } do
    body = %{
      repository_url: @remote,
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
           |> post(git_history_url(user, project, "/commits/missing"), %{repository_url: @remote, shas: ["a", "b", "c"]})
           |> json_response(:ok) ==
             %{"missing" => ["c"]}

    repository = GitHistory.repository_id(user.account.id, "git@github.com:acme/app.git")
    assert GitHistory.ancestors(repository, "b") == [{"b", 0}, {"a", 1}]
    assert GitHistory.branch_head(repository, "main") == "b"

    # Another project of the account on the same remote shares the graph.
    other = ProjectsFixtures.project_fixture(account_id: user.account.id)

    assert conn
           |> post(git_history_url(user, other, "/commits/missing"), %{repository_url: @remote, shas: ["a", "z"]})
           |> json_response(:ok) == %{"missing" => ["z"]}
  end

  test "uploads a commit's file listing in parts and reports which listings are missing", %{
    conn: conn,
    user: user,
    project: project
  } do
    assert conn
           |> post(git_history_url(user, project, "/listings/missing"), %{repository_url: @remote, shas: ["a"]})
           |> json_response(:ok) == %{"missing" => ["a"]}

    first = %{
      repository_url: @remote,
      sha: "a",
      files: [%{path: "Sources/A.swift", git_blob_id: "a1", mode: 33_188}],
      complete: false
    }

    assert conn |> post(git_history_url(user, project, "/listings"), first) |> response(:no_content)

    assert conn
           |> post(git_history_url(user, project, "/listings/missing"), %{repository_url: @remote, shas: ["a"]})
           |> json_response(:ok) == %{"missing" => ["a"]}

    last = %{
      repository_url: @remote,
      sha: "a",
      files: [%{path: "Package.resolved", git_blob_id: "p1"}],
      complete: true,
      truncated: false,
      files_count: 2
    }

    assert conn |> post(git_history_url(user, project, "/listings"), last) |> response(:no_content)

    assert conn
           |> post(git_history_url(user, project, "/listings/missing"), %{repository_url: @remote, shas: ["a"]})
           |> json_response(:ok) == %{"missing" => []}

    repository = GitHistory.repository_id(user.account.id, @remote)
    assert %{files_count: 2, truncated: false} = GitHistory.listing(repository, "a")
    assert Enum.map(GitHistory.commit_files(repository, "a"), & &1.path) == ["Package.resolved", "Sources/A.swift"]
  end

  test "rejects a remote that names no repository", %{conn: conn, user: user, project: project} do
    assert conn
           |> post(git_history_url(user, project, "/commits/missing"), %{repository_url: "not a remote", shas: ["a"]})
           |> json_response(:bad_request)
  end

  test "refuses a user without access to the project", %{conn: conn, user: user} do
    other = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: other.account.id)

    conn = get(conn, "/api/projects/#{other.account.name}/#{project.name}/tests/git-history/settings")
    assert conn.status in [403, 404]
    refute user.account.id == other.account.id
  end
end
