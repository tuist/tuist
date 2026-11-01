defmodule Tuist.Runners.CacheVolumes.IdentityClaimsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.KeyValueStore
  alias Tuist.Repo
  alias Tuist.Runners.CacheVolumes.Identity
  alias Tuist.Runners.CacheVolumes.Volume
  alias Tuist.Runners.RunnerSession
  alias Tuist.VCS
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    stub(KeyValueStore, :get_or_update, fn _key, _opts, func -> func.() end)
    stub(VCS, :get_github_app_installation_for_account, fn _ -> {:ok, %{installation_id: "99", client_url: nil}} end)
    account = AccountsFixtures.account_fixture()

    job = %{
      provider: "github",
      account_id: account.id,
      workflow_job_id: System.unique_integer([:positive]),
      workflow_run_id: 321,
      run_attempt: 1,
      repository: "org/repo"
    }

    %{account: account, job: job}
  end

  defp bind(job, claims) do
    Repo.insert!(%RunnerSession{
      account_id: job.account_id,
      workflow_job_id: job.workflow_job_id,
      executed_workflow_job_id: job.workflow_job_id,
      fleet_name: "linux",
      pod_name: "pod",
      node_name: "node",
      platform: :linux,
      vcpus: 2,
      memory_gb: 8,
      billing_multiplier: 10_000,
      started_at: DateTime.utc_now(),
      execution_identity:
        Map.merge(
          %{
            "workflow_job_id" => job.workflow_job_id,
            "repository_id" => "123",
            "repository" => "org/repo",
            "ref" => "refs/heads/main",
            "ref_type" => "branch",
            "event_name" => "push",
            "run_id" => "321",
            "run_attempt" => "1"
          },
          claims
        )
    })
  end

  defp default_branch(branch) do
    stub(GitHubClient, :get_repository, fn _, "org/repo" ->
      {:ok, %{"id" => 123, "full_name" => "org/repo", "default_branch" => branch}}
    end)
  end

  test "a push job's identity comes from its token without reading the run", %{job: job} do
    bind(job, %{})
    default_branch("main")
    reject(&GitHubClient.get_workflow_run/1)

    assert {:ok,
            %{repository_id: 123, trusted: true, same_repository: true, default_branch: "main", writer_branch: "main"}} =
             Identity.resolve(job)
  end

  test "a push to another branch or a tag is the repository's own but not the default branch", %{job: job} do
    default_branch("main")
    reject(&GitHubClient.get_workflow_run/1)

    bind(job, %{"ref" => "refs/tags/v1.0", "ref_type" => "tag"})
    assert {:ok, %{trusted: false, same_repository: true, writer_branch: "v1.0"}} = Identity.resolve(job)
  end

  test "the default branch the volumes recorded stands in when GitHub cannot answer", %{account: account, job: job} do
    bind(job, %{"event_name" => "schedule"})
    stub(GitHubClient, :get_repository, fn _, _ -> {:error, :server_error} end)
    reject(&GitHubClient.get_workflow_run/1)

    Repo.insert!(%Volume{
      account_id: account.id,
      repository_id: 123,
      scope_id: "123",
      repository: "org/repo",
      default_branch: "main",
      key: "gradle",
      architecture: "amd64",
      uid: 1001
    })

    assert {:ok, %{trusted: true, writer_branch: "main", default_branch: "main"}} = Identity.resolve(job)
  end

  test "without any default branch a push job reads but saves nothing", %{job: job} do
    bind(job, %{})
    stub(GitHubClient, :get_repository, fn _, _ -> {:error, :server_error} end)
    stub(GitHubClient, :get_workflow_run, fn _ -> {:error, :server_error} end)

    assert {:ok, identity} = Identity.resolve(job)
    assert identity == %{repository_id: 123, trusted: false, same_repository: true, writer_branch: nil}
  end

  test "a pull request job still reads the run, and reads without saving when GitHub cannot answer", %{job: job} do
    bind(job, %{"event_name" => "pull_request", "ref" => "refs/pull/7/merge", "head_ref" => "feature"})
    stub(GitHubClient, :get_workflow_run, fn _ -> {:error, :server_error} end)

    assert {:ok, identity} = Identity.resolve(job)
    assert identity == %{repository_id: 123, trusted: false, same_repository: false, writer_branch: nil}

    run = %{
      "id" => 321,
      "run_attempt" => 1,
      "head_repository" => %{"id" => 123},
      "head_branch" => "feature",
      "event" => "pull_request",
      "pull_requests" => [%{"head" => %{"repo" => %{"id" => 123}, "ref" => "feature"}}],
      "repository" => %{"id" => 123}
    }

    stub(GitHubClient, :get_workflow_run, fn _ -> {:ok, run} end)
    default_branch("main")

    assert {:ok, %{same_repository: true, writer_branch: "feature", default_branch: "main"}} = Identity.resolve(job)
  end

  test "claims for another job, run attempt or repository are ignored", %{job: job} do
    for claims <- [
          %{"workflow_job_id" => job.workflow_job_id + 1},
          %{"run_attempt" => "2"},
          %{"repository" => "org/other"}
        ] do
      session = bind(job, claims)
      expect(GitHubClient, :get_workflow_run, fn _ -> {:error, :server_error} end)
      assert {:error, :unavailable} = Identity.resolve(job)
      Repo.delete!(session)
    end
  end

  test "a session bound by GitHub's report alone resolves through the run as before", %{job: job} do
    bind(job, %{})
    Repo.update_all(RunnerSession, set: [execution_identity: nil])
    expect(GitHubClient, :get_workflow_run, fn _ -> {:error, :server_error} end)

    assert {:error, :unavailable} = Identity.resolve(job)
  end
end
