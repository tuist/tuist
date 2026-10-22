defmodule Tuist.Runners.CacheVolumes.IdentityTest do
  use ExUnit.Case, async: true

  import Mimic

  alias Tuist.Runners.Buildkite
  alias Tuist.Runners.CacheVolumes.Identity
  alias Tuist.Runners.GitLab

  setup :verify_on_exit!

  defp buildkite do
    job = %Buildkite.Job{
      job_uuid: Ecto.UUID.generate(),
      build_uuid: Ecto.UUID.generate(),
      build_number: 42,
      organization_slug: "org",
      pipeline_slug: "pipeline"
    }

    payload = %{
      "id" => job.job_uuid,
      "env" => %{
        "BUILDKITE_JOB_ID" => job.job_uuid,
        "BUILDKITE_BUILD_ID" => job.build_uuid,
        "BUILDKITE_BUILD_NUMBER" => "42",
        "BUILDKITE_ORGANIZATION_SLUG" => "org",
        "BUILDKITE_ORGANIZATION_ID" => Ecto.UUID.generate(),
        "BUILDKITE_PIPELINE_ID" => Ecto.UUID.generate(),
        "BUILDKITE_PIPELINE_SLUG" => "pipeline",
        "BUILDKITE_REPO" => "git@github.com:org/repo.git",
        "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main",
        "BUILDKITE_BRANCH" => "main",
        "BUILDKITE_PULL_REQUEST" => "false",
        "BUILDKITE_SOURCE" => "webhook"
      }
    }

    {job, payload}
  end

  test "Buildkite scopes use immutable pipeline and organization plus repository identity" do
    {job, payload} = buildkite()
    assert {:ok, %{trusted: true} = identity} = Identity.buildkite_identity(job, payload)
    assert identity.provider == "buildkite"

    assert {:ok, renamed} =
             Identity.buildkite_identity(
               %{job | pipeline_slug: "renamed"},
               put_in(payload, ["env", "BUILDKITE_PIPELINE_SLUG"], "renamed")
             )

    assert identity.scope_id == renamed.scope_id
    assert {:ok, repointed} = Identity.buildkite_identity(job, put_in(payload, ["env", "BUILDKITE_REPO"], "other"))
    refute identity.scope_id == repointed.scope_id

    assert {:ok, other_org} =
             Identity.buildkite_identity(job, put_in(payload, ["env", "BUILDKITE_ORGANIZATION_ID"], Ecto.UUID.generate()))

    refute identity.provider_instance == other_org.provider_instance
  end

  test "Buildkite rejects mismatched assignments and missing identity fields" do
    {job, payload} = buildkite()

    for field <- [
          "BUILDKITE_JOB_ID",
          "BUILDKITE_BUILD_ID",
          "BUILDKITE_BUILD_NUMBER",
          "BUILDKITE_ORGANIZATION_SLUG",
          "BUILDKITE_PIPELINE_SLUG",
          "BUILDKITE_ORGANIZATION_ID",
          "BUILDKITE_PIPELINE_ID",
          "BUILDKITE_REPO"
        ] do
      assert {:error, :unavailable} = Identity.buildkite_identity(job, update_in(payload["env"], &Map.delete(&1, field)))
    end

    assert {:error, :unavailable} = Identity.buildkite_identity(job, %{payload | "id" => Ecto.UUID.generate()})
  end

  test "Buildkite pull requests, nondefault branches, tags and manual builds cannot publish" do
    {job, payload} = buildkite()

    for {field, value} <- [
          {"BUILDKITE_BRANCH", "feature"},
          {"BUILDKITE_PULL_REQUEST", "42"},
          {"BUILDKITE_PULL_REQUEST", nil},
          {"BUILDKITE_TAG", "v1"},
          {"BUILDKITE_SOURCE", "ui"},
          {"BUILDKITE_SOURCE", "api"},
          {"BUILDKITE_SOURCE", nil},
          {"BUILDKITE_PIPELINE_DEFAULT_BRANCH", nil}
        ] do
      assert {:ok, %{trusted: false}} = Identity.buildkite_identity(job, put_in(payload, ["env", field], value))
    end

    assert {:ok, %{trusted: true}} =
             Identity.buildkite_identity(job, put_in(payload, ["env", "BUILDKITE_SOURCE"], "schedule"))
  end

  test "Buildkite profile writers are webhook and schedule builds of the pipeline's repository" do
    {job, payload} = buildkite()
    feature = put_in(payload, ["env", "BUILDKITE_BRANCH"], "feature")

    for source <- ["webhook", "schedule"] do
      assert {:ok, %{trusted: false, writer_branch: "feature"}} =
               Identity.buildkite_identity(job, put_in(feature, ["env", "BUILDKITE_SOURCE"], source))
    end

    assert {:ok, %{trusted: true, writer_branch: "main"}} = Identity.buildkite_identity(job, payload)

    pull_request =
      update_in(feature["env"], &Map.put(&1, "BUILDKITE_PULL_REQUEST", "42"))

    for repository <- ["https://github.com/org/repo.git", "git@github.com:org/repo.git", "https://GitHub.com/org/repo"] do
      same_repository = put_in(pull_request, ["env", "BUILDKITE_PULL_REQUEST_REPO"], repository)

      assert {:ok, %{trusted: false, writer_branch: "feature"}} =
               Identity.buildkite_identity(job, same_repository)
    end

    for {field, value} <- [
          {"BUILDKITE_PULL_REQUEST_REPO", "https://github.com/fork/repo.git"},
          {"BUILDKITE_PULL_REQUEST_REPO", "https://gitlab.com/org/repo.git"},
          {"BUILDKITE_PULL_REQUEST_REPO", ""},
          {"BUILDKITE_PULL_REQUEST_REPO", nil}
        ] do
      assert {:ok, %{writer_branch: nil}} = Identity.buildkite_identity(job, put_in(pull_request, ["env", field], value))
    end

    for {field, value} <- [
          {"BUILDKITE_PULL_REQUEST", nil},
          {"BUILDKITE_TAG", "v1"},
          {"BUILDKITE_SOURCE", "ui"},
          {"BUILDKITE_SOURCE", "api"},
          {"BUILDKITE_SOURCE", "trigger_job"},
          {"BUILDKITE_SOURCE", nil},
          {"BUILDKITE_BRANCH", ""}
        ] do
      assert {:ok, %{writer_branch: nil}} = Identity.buildkite_identity(job, put_in(feature, ["env", field], value))
    end
  end

  test "Buildkite resolves the captured identity after the scheduling payload disappears" do
    {assigned, payload} = buildkite()
    {:ok, identity} = Identity.buildkite_identity(assigned, payload)
    stored = Map.new(identity, fn {key, value} -> {Atom.to_string(key), value} end)
    assigned = %{assigned | account_id: 1, cache_volume_identity: stored}
    stub(Buildkite, :get_job, fn 42 -> assigned end)
    stub(Buildkite, :get_installation, fn 1 -> %Buildkite.Installation{enabled: true} end)

    assert {:ok, ^identity} = Identity.resolve(%{provider: "buildkite", account_id: 1, workflow_job_id: 42})
    assert {:error, :unavailable} = Identity.resolve(%{provider: "buildkite", account_id: 2, workflow_job_id: 42})

    stub(Buildkite, :get_job, fn 42 -> %{assigned | cache_volume_identity: nil} end)
    assert {:error, :unavailable} = Identity.resolve(%{provider: "buildkite", account_id: 1, workflow_job_id: 42})

    stub(Buildkite, :get_job, fn 42 -> assigned end)
    stub(Buildkite, :get_installation, fn 1 -> %Buildkite.Installation{enabled: false} end)
    assert {:error, :unavailable} = Identity.resolve(%{provider: "buildkite", account_id: 1, workflow_job_id: 42})
  end

  defp gitlab do
    job = %GitLab.Job{job_id: 42, url: "https://gitlab.com", pipeline_id: 5}
    payload = %{"id" => 42, "job_info" => %{"project_id" => 123}, "git_info" => %{"sha" => "abc"}}

    remote = %{
      "id" => 42,
      "status" => "running",
      "pipeline" => %{"id" => 5, "project_id" => 123, "source" => "push"},
      "commit" => %{"id" => "abc"},
      "ref" => "main",
      "tag" => false
    }

    {job, payload, remote}
  end

  test "GitLab verifies the assigned job, project and commit independently of CI variables" do
    {job, payload, remote} = gitlab()
    payload = Map.put(payload, "variables", [%{"key" => "CI_PROJECT_ID", "value" => "999"}])
    assert {:ok, %{scope_id: "123", trusted: false} = identity} = Identity.gitlab_identity(job, payload, remote)
    assert {:ok, other} = Identity.gitlab_identity(%{job | url: "https://gitlab.example.com"}, payload, remote)
    refute identity.provider_instance == other.provider_instance

    for bad <- [
          %{remote | "id" => 43},
          %{remote | "status" => "success"},
          put_in(remote, ["pipeline", "project_id"], 999),
          put_in(remote, ["commit", "id"], "other"),
          %{remote | "ref" => nil}
        ] do
      assert {:error, :unavailable} = Identity.gitlab_identity(job, payload, bad)
    end

    assert {:error, :unavailable} = Identity.gitlab_identity(job, %{}, %{})
  end

  test "GitLab resolver uses the persisted token and refuses another account's assignment" do
    {assigned, payload, remote} = gitlab()
    job = %{provider: "gitlab", account_id: 7, workflow_job_id: 10}
    assigned = %{assigned | account_id: 7, payload: JSON.encode!(Map.put(payload, "token", "assigned-token"))}
    expect(GitLab, :get_job, fn 10 -> assigned end)
    expect(GitLab.Client, :get_running_job, fn "https://gitlab.com", "assigned-token" -> {:ok, remote} end)

    expect(GitLab.Client, :cache_branches, fn "https://gitlab.com", "assigned-token", 123, "main" ->
      {:ok, [%{"name" => "main", "default" => true}]}
    end)

    assert {:ok, %{trusted: true, scope_id: "123"}} = Identity.resolve(job)

    expect(GitLab, :get_job, fn 10 -> %{assigned | account_id: 8} end)
    reject(GitLab.Client, :get_running_job, 2)
    assert {:error, :unavailable} = Identity.resolve(job)
  end

  test "GitLab API failures and invalid stored payloads cannot authorize allocation" do
    {assigned, payload, _remote} = gitlab()
    job = %{provider: "gitlab", account_id: 7, workflow_job_id: 10}

    for invalid <- [nil, "null", "[]", "{}", "invalid-json"] do
      expect(GitLab, :get_job, fn 10 -> %{assigned | account_id: 7, payload: invalid} end)
      assert {:error, :unavailable} = Identity.resolve(job)
    end

    assigned = %{assigned | account_id: 7, payload: JSON.encode!(Map.put(payload, "token", "assigned-token"))}
    expect(GitLab, :get_job, fn 10 -> assigned end)
    expect(GitLab.Client, :get_running_job, fn _, _ -> {:error, :unauthorized} end)
    assert {:error, :unavailable} = Identity.resolve(job)
  end

  test "Buildkite rejects incomplete captured identities" do
    {assigned, _} = buildkite()
    stub(Buildkite, :get_installation, fn 7 -> %Buildkite.Installation{enabled: true} end)

    for identity <- [nil, %{}, %{"trusted" => true}, %{"provider" => "github"}] do
      expect(Buildkite, :get_job, fn 10 -> %{assigned | account_id: 7, cache_volume_identity: identity} end)
      assert {:error, :unavailable} = Identity.resolve(%{provider: "buildkite", account_id: 7, workflow_job_id: 10})
    end
  end

  test "Buildkite identities captured without a writer branch resolve without one" do
    {assigned, _} = buildkite()
    stub(Buildkite, :get_installation, fn 7 -> %Buildkite.Installation{enabled: true} end)

    stored = %{"provider" => "buildkite", "provider_instance" => "org", "scope_id" => "pipeline:repo", "trusted" => true}

    for writer_branch <- [:missing, nil, "", 42] do
      identity = if writer_branch == :missing, do: stored, else: Map.put(stored, "writer_branch", writer_branch)
      expect(Buildkite, :get_job, fn 10 -> %{assigned | account_id: 7, cache_volume_identity: identity} end)

      assert {:ok, %{trusted: true, writer_branch: nil}} =
               Identity.resolve(%{provider: "buildkite", account_id: 7, workflow_job_id: 10})
    end
  end

  test "GitLab save permission requires authoritative default branch and non-MR source" do
    {_job, _payload, remote} = gitlab()
    branches = [%{"name" => "main", "default" => true}]
    assert Identity.gitlab_writer?(remote, branches)

    for source <- ["merge_request_event", "external_pull_request_event", "parent_pipeline", "api", nil] do
      denied = put_in(remote, ["pipeline", "source"], source)
      refute Identity.gitlab_writer?(denied, branches)
      refute Identity.gitlab_writer?(Map.put(denied, "source", "push"), branches)
    end

    refute Identity.gitlab_writer?(%{remote | "tag" => true}, branches)
    refute Identity.gitlab_writer?(%{remote | "ref" => "feature"}, branches)
    refute Identity.gitlab_writer?(remote, [%{"name" => "main", "default" => false}])
    refute Identity.gitlab_writer?(remote, [nil, %{}, "invalid"])
    refute Identity.gitlab_writer?(remote, nil)
  end

  test "GitLab supports job responses with only a top-level source" do
    {_job, _payload, remote} = gitlab()
    branches = [%{"name" => "main", "default" => true}]
    remote = update_in(remote, ["pipeline"], &Map.delete(&1, "source"))

    for source <- ["push", "schedule", "web"] do
      assert Identity.gitlab_writer?(Map.put(remote, "source", source), branches)
      assert Identity.gitlab_writer?(put_in(remote, ["pipeline", "source"], source), branches)
    end

    refute Identity.gitlab_writer?(remote, branches)
    refute Identity.gitlab_writer?(Map.put(remote, "source", "api"), branches)
  end

  test "GitLab profile writers are branch pipelines of the project, never merge requests or tags" do
    {_job, _payload, remote} = gitlab()
    feature = %{remote | "ref" => "feature/x"}

    for source <- ["push", "schedule", "web"] do
      assert Identity.gitlab_writer_branch(put_in(feature, ["pipeline", "source"], source)) == "feature/x"
    end

    assert Identity.gitlab_writer_branch(remote) == "main"

    for source <- ["merge_request_event", "external_pull_request_event", "parent_pipeline", "api", "trigger", nil] do
      merge_request = %{put_in(feature, ["pipeline", "source"], source) | "ref" => "refs/merge-requests/1/merge"}
      assert is_nil(Identity.gitlab_writer_branch(merge_request))
      assert is_nil(Identity.gitlab_writer_branch(put_in(feature, ["pipeline", "source"], source)))
    end

    for bad <- [%{feature | "tag" => true}, Map.delete(feature, "tag"), %{feature | "ref" => ""}, %{}] do
      assert is_nil(Identity.gitlab_writer_branch(bad))
    end
  end

  test "GitLab merge request numbers come only from the GitLab-set merge request ref" do
    {_job, _payload, remote} = gitlab()
    merge_request = put_in(remote, ["pipeline", "source"], "merge_request_event")

    for {ref, iid} <- [
          {"refs/merge-requests/7/head", 7},
          {"refs/merge-requests/4846/merge", 4846},
          {"refs/merge-requests/12/train", 12}
        ] do
      assert {:ok, ^iid} = Identity.gitlab_merge_request_iid(%{merge_request | "ref" => ref})
    end

    for ref <- [
          "main",
          "refs/merge-requests/0/merge",
          "refs/merge-requests/abc/merge",
          "refs/merge-requests/7/merge/extra",
          "refs/merge-requests/7/other",
          "xrefs/merge-requests/7/merge"
        ] do
      assert :error = Identity.gitlab_merge_request_iid(%{merge_request | "ref" => ref})
    end

    with_ref = %{merge_request | "ref" => "refs/merge-requests/7/merge"}

    for denied <- [
          put_in(with_ref, ["pipeline", "source"], "push"),
          %{with_ref | "tag" => true},
          Map.delete(with_ref, "tag")
        ] do
      assert :error = Identity.gitlab_merge_request_iid(denied)
    end
  end

  test "GitLab merge requests save only when the project is both their target and source" do
    merge_request = %{"iid" => 7, "project_id" => 123, "source_project_id" => 123, "source_branch" => "feature"}
    assert Identity.gitlab_merge_request_source_branch(merge_request, 123, 7) == "feature"

    for denied <- [
          %{merge_request | "source_project_id" => 999},
          %{merge_request | "project_id" => 999, "source_project_id" => 999},
          %{merge_request | "iid" => 8},
          %{merge_request | "source_branch" => ""},
          Map.delete(merge_request, "source_project_id"),
          nil
        ] do
      assert is_nil(Identity.gitlab_merge_request_source_branch(denied, 123, 7))
    end
  end

  test "GitLab merge request pipelines write under the source branch only with the connection's API token" do
    {assigned, payload, remote} = gitlab()
    job = %{provider: "gitlab", account_id: 7, workflow_job_id: 10}

    assigned = %{
      assigned
      | account_id: 7,
        connection_id: 3,
        payload: JSON.encode!(Map.put(payload, "token", "assigned-token"))
    }

    remote = %{put_in(remote, ["pipeline", "source"], "merge_request_event") | "ref" => "refs/merge-requests/4846/merge"}
    connection = %GitLab.Connection{id: 3, account_id: 7, url: "https://gitlab.com", api_token: "glpat-secret"}
    stub(GitLab, :get_job, fn 10 -> assigned end)
    stub(GitLab.Client, :get_running_job, fn _, _ -> {:ok, remote} end)
    stub(GitLab.Client, :cache_branches, fn _, _, 123, _ -> {:ok, []} end)

    expect(GitLab, :get_connection, fn 3 -> connection end)

    expect(GitLab.Client, :get_merge_request, fn "https://gitlab.com", "glpat-secret", 123, 4846 ->
      {:ok, %{"iid" => 4846, "project_id" => 123, "source_project_id" => 123, "source_branch" => "feature/x"}}
    end)

    assert {:ok, %{trusted: false, writer_branch: "feature/x"}} = Identity.resolve(job)

    expect(GitLab, :get_connection, fn 3 -> connection end)

    expect(GitLab.Client, :get_merge_request, fn _, _, _, _ ->
      {:ok, %{"iid" => 4846, "project_id" => 123, "source_project_id" => 999, "source_branch" => "feature/x"}}
    end)

    assert {:ok, %{writer_branch: nil}} = Identity.resolve(job)

    expect(GitLab, :get_connection, fn 3 -> connection end)
    expect(GitLab.Client, :get_merge_request, fn _, _, _, _ -> {:error, :unauthorized} end)
    assert {:ok, %{writer_branch: nil}} = Identity.resolve(job)

    reject(GitLab.Client, :get_merge_request, 4)

    for other <- [
          %{connection | api_token: nil},
          %{connection | api_token: ""},
          %{connection | account_id: 8},
          %{connection | url: "https://gitlab.example.com"},
          nil
        ] do
      expect(GitLab, :get_connection, fn 3 -> other end)
      assert {:ok, %{writer_branch: nil}} = Identity.resolve(job)
    end

    stub(GitLab, :get_job, fn 10 -> %{assigned | connection_id: nil} end)
    reject(GitLab, :get_connection, 1)
    assert {:ok, %{writer_branch: nil}} = Identity.resolve(job)
  end

  test "GitLab resolves the writer branch of a nondefault branch pipeline" do
    {assigned, payload, remote} = gitlab()
    job = %{provider: "gitlab", account_id: 7, workflow_job_id: 10}
    assigned = %{assigned | account_id: 7, payload: JSON.encode!(Map.put(payload, "token", "assigned-token"))}
    expect(GitLab, :get_job, fn 10 -> assigned end)
    expect(GitLab.Client, :get_running_job, fn _, _ -> {:ok, %{remote | "ref" => "feature"}} end)

    expect(GitLab.Client, :cache_branches, fn _, _, 123, "feature" ->
      {:ok, [%{"name" => "feature", "default" => false}]}
    end)

    assert {:ok, %{trusted: false, writer_branch: "feature"}} = Identity.resolve(job)
  end

  test "GitHub profile writers use provider-verified branch and repository identity" do
    job = %{repository: "org/repo", workflow_run_id: 42, run_attempt: 1}

    run = %{
      "id" => 42,
      "run_attempt" => 1,
      "repository" => %{"id" => 123, "full_name" => "org/repo", "default_branch" => "main"},
      "head_repository" => %{"id" => 123},
      "head_branch" => "feature",
      "event" => "push"
    }

    for event <- ["push", "workflow_dispatch", "schedule"] do
      assert {:ok, %{trusted: false, writer_branch: "feature", default_branch: "main"}} =
               Identity.github_identity(job, %{run | "event" => event})
    end

    assert {:ok, %{trusted: true, writer_branch: "main"}} =
             Identity.github_identity(job, %{run | "head_branch" => "main"})

    for event <- ["pull_request_target", "merge_group", "unknown"] do
      assert {:ok, %{writer_branch: nil}} = Identity.github_identity(job, %{run | "event" => event})
    end

    pr =
      Map.merge(run, %{
        "event" => "pull_request",
        "pull_requests" => [%{"head" => %{"repo" => %{"id" => 123}, "ref" => "feature"}}]
      })

    assert {:ok, %{trusted: false, writer_branch: "feature"}} = Identity.github_identity(job, pr)

    for prs <- [
          [],
          [%{"head" => %{"repo" => %{"id" => 999}, "ref" => "feature"}}],
          [%{"head" => %{"repo" => %{"id" => 123}, "ref" => "other"}}]
        ] do
      assert {:ok, %{writer_branch: nil}} = Identity.github_identity(job, %{pr | "pull_requests" => prs})
    end

    for event <- ["pull_request", "push"] do
      assert {:ok, %{writer_branch: nil}} =
               Identity.github_identity(job, %{pr | "event" => event, "head_repository" => %{"id" => 999}})
    end
  end
end
