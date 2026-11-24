defmodule Tuist.Snapshots.Workers.CheckRunWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.GitHub.Client
  alias Tuist.Repo
  alias Tuist.Snapshots
  alias Tuist.Snapshots.Build
  alias Tuist.Snapshots.Workers.CheckRunWorker
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Webhooks.GitHubController

  setup do
    stub(Environment, :github_app_configured?, fn -> true end)
    project = ProjectsFixtures.project_fixture(vcs_connection: [repository_full_handle: "org/repo", provider: :github])
    %{project: project}
  end

  defp build(project, attrs) do
    Repo.insert!(
      struct(
        %Build{
          project_id: project.id,
          set_name: "phone",
          git_commit_sha: "abc123",
          git_branch: "feature",
          state: "processed",
          changed_count: 2,
          removed_count: 1,
          added_count: 1,
          unchanged_count: 5
        },
        attrs
      )
    )
  end

  defp perform(build), do: CheckRunWorker.perform(%Oban.Job{args: %{"build_id" => build.id}})

  test "asks for approval of changes, then completes the same check run once approved", %{project: project} do
    build = build(project, %{})

    expect(Client, :create_check_run, fn params ->
      assert params.name == "tuist/snapshots (phone)"
      assert params.head_sha == "abc123"
      assert params.external_id == build.id
      assert params.conclusion == "action_required"
      # Sentry's columns: added, removed, modified, renamed, unchanged, skipped.
      assert params.output.summary =~ "| phone | 1 | 1 | 2 | 0 | 5 | 0 | ⏳ Needs approval |"
      assert Enum.map(params.actions, & &1.identifier) == ["approve_snapshots", "reject_snapshots"]
      {:ok, %{"id" => 77}}
    end)

    assert :ok = perform(build)
    assert Repo.get!(Build, build.id).github_check_run_id == 77

    # The check run's Approve button, pressed on the build's repository.
    response =
      GitHubController.handle(Plug.Conn.put_req_header(build_conn(), "x-github-event", "check_run"), %{
        "action" => "requested_action",
        "check_run" => %{"id" => 77, "name" => "tuist/snapshots (phone)", "external_id" => build.id},
        "requested_action" => %{"identifier" => "approve_snapshots"},
        "repository" => %{"full_name" => "Org/Repo"},
        "sender" => %{"id" => 1, "login" => "octocat"}
      })

    assert response.status == 200
    approved = Repo.get!(Build, build.id)
    assert approved.approved_by_github_handle == "octocat"

    expect(Client, :update_check_run, fn params ->
      assert params.check_run_id == 77
      assert params.conclusion == "success"
      assert Enum.map(params.actions, & &1.identifier) == ["reject_snapshots"]
      assert params.output.summary =~ "Approved by @octocat."
      {:ok, %{"id" => 77}}
    end)

    assert :ok = perform(approved)
  end

  test "the Reject button fails the check and offers to approve instead", %{project: project} do
    build = build(project, %{github_check_run_id: 77})

    GitHubController.handle(Plug.Conn.put_req_header(build_conn(), "x-github-event", "check_run"), %{
      "action" => "requested_action",
      "check_run" => %{"id" => 77, "name" => "tuist/snapshots (phone)", "external_id" => build.id},
      "requested_action" => %{"identifier" => "reject_snapshots"},
      "repository" => %{"full_name" => "org/repo"},
      "sender" => %{"id" => 1, "login" => "octocat"}
    })

    rejected = Repo.get!(Build, build.id)
    assert Snapshots.status(rejected, project) == "rejected"
    assert rejected.rejected_by_github_handle == "octocat"

    expect(Client, :update_check_run, fn params ->
      assert params.conclusion == "failure"
      assert params.output.title == "Snapshot changes rejected"
      assert params.output.summary =~ "❌ Rejected |"
      assert params.output.summary =~ "Rejected by @octocat."
      assert Enum.map(params.actions, & &1.identifier) == ["approve_snapshots"]
      {:ok, %{"id" => 77}}
    end)

    assert :ok = perform(rejected)
  end

  test "ignores an Approve press from another repository", %{project: project} do
    build = build(project, %{})

    GitHubController.handle(Plug.Conn.put_req_header(build_conn(), "x-github-event", "check_run"), %{
      "action" => "requested_action",
      "check_run" => %{"id" => 77, "name" => "tuist/snapshots (phone)", "external_id" => build.id},
      "requested_action" => %{"identifier" => "approve_snapshots"},
      "repository" => %{"full_name" => "someone/else"},
      "sender" => %{"id" => 1, "login" => "mallory"}
    })

    assert Snapshots.status(Repo.get!(Build, build.id), project) == "needs_review"
  end

  test "posts a pull request merge commit's check on the pull request's head", %{project: project} do
    build = build(project, %{git_commit_sha: "merge123", git_ref: "refs/pull/7/merge", pull_request_number: 7})

    expect(Client, :get_git_commit, fn %{sha: "merge123"} ->
      {:ok, %{"parents" => [%{"sha" => "base456"}, %{"sha" => "head789"}]}}
    end)

    expect(Client, :create_check_run, fn params ->
      assert params.head_sha == "head789"
      {:ok, %{"id" => 77}}
    end)

    assert :ok = perform(build)
  end

  test "posts nothing for default branch builds", %{project: project} do
    reject(&Client.create_check_run/1)
    assert :ok = perform(build(project, %{git_branch: project.default_branch}))
  end

  defp build_conn, do: Phoenix.ConnTest.build_conn()
end
