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

  test "Buildkite resolver fetches the account's exact assigned job from Stacks" do
    {assigned, payload} = buildkite()
    assigned = %{assigned | account_id: 7, queue_key: "linux"}
    installation = %Buildkite.Installation{enabled: true}
    expect(Buildkite, :get_job, fn 10 -> assigned end)
    expect(Buildkite, :get_installation, fn 7 -> installation end)
    expect(Buildkite, :stack_key_for, fn ^installation, "linux" -> "stack" end)

    expect(Buildkite.Client, :get_job, fn ^installation, "stack", id ->
      assert id == assigned.job_uuid
      {:ok, payload}
    end)

    assert {:ok, %{trusted: true}} = Identity.resolve(%{provider: "buildkite", account_id: 7, workflow_job_id: 10})
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

  test "GitLab supports older job responses with only a top-level source" do
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
end
