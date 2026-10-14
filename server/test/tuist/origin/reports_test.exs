defmodule Tuist.Origin.ReportsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Origin.Client
  alias Tuist.Origin.Installation
  alias Tuist.Origin.Reports
  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    project = ProjectsFixtures.project_fixture()

    {:ok, installation} =
      Repo.insert(
        Installation.changeset(%Installation{}, %{
          account_id: project.account_id,
          installation_id: "inst-#{project.id}",
          namespace_id: "ns-#{project.id}",
          namespace_slug: "org"
        })
      )

    {:ok, _} =
      Projects.create_vcs_connection(%{
        project_id: project.id,
        provider: :origin,
        repository_full_handle: "org/repo",
        origin_repository_id: "repo-1",
        origin_app_installation_id: installation.id
      })

    stub(Environment, :origin_app_credentials, fn -> %{app_id: "app-tuist"} end)

    stub(Client, :repositories, fn _ ->
      {:ok, [%{"id" => "repo-1", "fullName" => "org/repo", "webUrl" => "https://cursor.com/codebase/org/repo"}]}
    end)

    stub(Client, :get_pull_request, fn _, _, _ ->
      {:ok, %{"state" => "open", "number" => "7", "head" => %{"sha" => "current-head"}}}
    end)

    params = %{
      project: project,
      git_remote_url_origin: "https://origin.cursor.com/git/org/repo.git",
      git_ref: "refs/pull/7/merge",
      git_commit_sha: "current-head"
    }

    %{params: params}
  end

  test "updates only this project's comment authored by the configured app", %{params: params} do
    marker = "<!-- tuist-project:#{params.project.id} -->"

    stub(Client, :comments, fn _, _, _ ->
      {:ok,
       [
         %{"id" => "human", "body" => "old\n#{marker}", "author" => %{"user" => %{"id" => "user"}}},
         %{
           "id" => "other-project",
           "body" => "old\n<!-- tuist-project:0 -->",
           "author" => %{"app" => %{"id" => "app-tuist"}}
         },
         %{"id" => "own", "body" => "old\n#{marker}", "author" => %{"app" => %{"id" => "app-tuist"}}}
       ]}
    end)

    stub(Client, :update_comment, fn _, "org/repo", "own", body ->
      assert body == "report\n#{marker}"
      {:ok, %{}}
    end)

    assert :ok = Reports.post_comment(params, fn _ -> "report" end)
  end

  test "publishes after a repository rename without waiting for an installation webhook", %{params: params} do
    stub(Client, :repositories, fn _ ->
      {:ok, [%{"id" => "repo-1", "fullName" => "org/renamed", "webUrl" => "https://cursor.com/codebase/org/renamed"}]}
    end)

    stub(Client, :get_pull_request, fn _, "org/renamed", 7 ->
      {:ok, %{"state" => "open", "number" => "7", "head" => %{"sha" => "current-head"}}}
    end)

    stub(Client, :comments, fn _, "org/renamed", 7 -> {:ok, []} end)

    stub(Client, :create_comment, fn _, "org/renamed", 7, _ -> {:ok, %{}} end)

    assert :ok =
             Reports.post_comment(
               %{params | git_remote_url_origin: "https://origin.cursor.com/org/renamed.git"},
               fn p ->
                 assert p.git_remote_url_origin == "https://cursor.com/codebase/org/renamed"
                 "report"
               end
             )

    assert Repo.preload(params.project, :vcs_connection).vcs_connection.repository_full_handle == "org/renamed"
  end

  test "rejects foreign remotes and obsolete merge previews, and preserves retryable API errors", %{params: params} do
    render = fn _ -> flunk("Unrelated or stale results must not be published") end

    for remote <- [
          "https://github.com/org/repo.git",
          "https://origin.cursor.com/git/fork/repo.git",
          "https://origin.cursor.com.evil.test/git/org/repo.git"
        ] do
      assert :ok = Reports.post_comment(%{params | git_remote_url_origin: remote}, render)
    end

    stub(Client, :get_git_ref, fn _, _, _ -> {:ok, %{"object" => %{"sha" => "old-merge"}}} end)
    stub(Client, :get_git_commit, fn _, _, _ -> {:ok, %{"parents" => [%{"sha" => "base"}, %{"sha" => "old-head"}]}} end)
    assert :ok = Reports.post_comment(%{params | git_commit_sha: "old-merge"}, render)

    stub(Client, :comments, fn _, _, _ -> {:error, {:http, 503}} end)
    assert {:error, {:http, 503}} = Reports.post_comment(params, fn _ -> "report" end)
  end

  test "accepts a merge preview only when it contains the current PR head", %{params: params} do
    stub(Client, :get_git_ref, fn _, _, _ -> {:ok, %{"object" => %{"sha" => "current-merge"}}} end)

    stub(Client, :get_git_commit, fn _, _, _ ->
      {:ok, %{"parents" => [%{"sha" => "base"}, %{"sha" => "current-head"}]}}
    end)

    stub(Client, :comments, fn _, _, _ -> {:ok, []} end)

    stub(Client, :create_comment, fn _, _, 7, body ->
      assert body =~ "report\n<!-- tuist-project:"
      {:ok, %{}}
    end)

    assert :ok = Reports.post_comment(%{params | git_commit_sha: "current-merge"}, fn _ -> "report" end)
  end
end
