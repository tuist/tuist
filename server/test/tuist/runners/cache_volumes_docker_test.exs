defmodule Tuist.Runners.CacheVolumesDockerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query, only: [from: 2]
  import Mimic

  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Repo
  alias Tuist.Runners.CacheVolumes
  alias Tuist.Runners.CacheVolumes.Usage
  alias Tuist.Runners.CacheVolumes.Volume
  alias Tuist.Runners.Profile
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.WorkflowJob
  alias Tuist.VCS
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @image_id "sha256:" <> String.duplicate("a", 64)

  setup do
    stub(Environment, :runner_cache_volumes_enabled?, fn _ -> true end)
    account = AccountsFixtures.account_fixture()

    job = %{
      account_id: account.id,
      workflow_job_id: System.unique_integer([:positive]),
      workflow_run_id: 321,
      run_attempt: 1,
      repository: "org/repo",
      head_sha: String.duplicate("a", 40),
      head_branch: "main"
    }

    Repo.insert!(
      struct(
        WorkflowJob,
        Map.merge(job, %{provider: "github", status: "running", fleet_name: "linux", enqueued_at: DateTime.utc_now()})
      )
    )

    session(account, job, "linux-pod", :linux)

    stub(VCS, :get_github_app_installation_for_account, fn _ -> {:ok, %{installation_id: "99", client_url: nil}} end)
    stub_run(job, %{"head_branch" => "main", "event" => "push"})

    stub(GitHubClient, :get_repository, fn _, _ ->
      {:ok, %{"id" => 123, "full_name" => job.repository, "default_branch" => "main"}}
    end)

    params = %{
      "pod_name" => "linux-pod",
      "pod_uid" => "linux-uid",
      "node_name" => "linux-node",
      "architecture" => "amd64",
      "uid" => 0,
      "max_volume_bytes" => 100_000_000_000
    }

    %{account: account, job: job, params: params}
  end

  defp session(account, job, pod, platform) do
    Repo.insert!(%RunnerSession{
      account_id: account.id,
      workflow_job_id: job.workflow_job_id,
      executed_workflow_job_id: job.workflow_job_id,
      fleet_name: to_string(platform),
      pod_name: pod,
      node_name: "linux-node",
      platform: platform,
      vcpus: 2,
      memory_gb: 8,
      billing_multiplier: 10_000,
      started_at: DateTime.utc_now()
    })
  end

  defp stub_run(job, run) do
    stub(GitHubClient, :get_workflow_run, fn _ ->
      {:ok,
       Map.merge(
         %{
           "id" => job.workflow_run_id,
           "run_attempt" => job.run_attempt,
           "repository" => %{"id" => 123},
           "head_repository" => %{"id" => 123}
         },
         run
       )}
    end)
  end

  defp docker_volumes(account), do: Repo.all(from(v in Volume, where: v.account_id == ^account.id and v.key == "docker"))

  defp report(extra) do
    Map.merge(
      %{
        "state" => "active",
        "gone" => true,
        "warm" => false,
        "size_bytes" => 1024,
        "capacity_bytes" => 2048,
        "attach_ms" => 10
      },
      extra
    )
  end

  test "a repository gets a data root once a job was seen using Docker", %{account: account, params: params} do
    assert {:error, :unseen} = CacheVolumes.allocate_docker(params)
    assert docker_volumes(account) == []

    assert :ok = CacheVolumes.mark_docker_seen(params)
    assert [%Volume{platform: "linux", architecture: "amd64", uid: 0, head_id: nil}] = docker_volumes(account)

    assert {:ok, docker} = CacheVolumes.allocate_docker(params)
    assert docker.volume_bytes == 100_000_000_000
    assert docker.can_publish
    assert docker.base_generation == 0
  end

  test "a job that already finished still marks its repository", %{account: account, job: job, params: params} do
    WorkflowJob
    |> Repo.get!(job.workflow_job_id)
    |> Ecto.Changeset.change(status: "completed")
    |> Repo.update!()

    assert :ok = CacheVolumes.mark_docker_seen(params)
    assert [_] = docker_volumes(account)
  end

  test "a fork's job neither gets a data root nor marks the repository", %{account: account, job: job, params: params} do
    assert :ok = CacheVolumes.mark_docker_seen(params)

    stub_run(job, %{
      "head_branch" => "feature",
      "event" => "pull_request",
      "head_repository" => %{"id" => 456},
      "pull_requests" => [%{"head" => %{"repo" => %{"id" => 456}, "ref" => "feature"}}]
    })

    assert {:error, :unavailable} = CacheVolumes.allocate_docker(params)
    assert {:error, :unavailable} = CacheVolumes.mark_docker_seen(params)

    assert Repo.aggregate(
             from(u in Usage, join: v in Volume, on: v.id == u.volume_id, where: v.account_id == ^account.id),
             :count
           ) == 0
  end

  test "a pull request from the repository reads the data root but its profile decides publication", %{
    job: job,
    params: params
  } do
    assert :ok = CacheVolumes.mark_docker_seen(params)

    stub_run(job, %{
      "head_branch" => "feature",
      "event" => "pull_request",
      "pull_requests" => [%{"head" => %{"repo" => %{"id" => 123}, "ref" => "feature"}}]
    })

    assert {:ok, %{can_publish: true}} = CacheVolumes.allocate_docker(params)
  end

  test "the runner profile turns the Docker cache off", %{account: account, job: job, params: params} do
    assert :ok = CacheVolumes.mark_docker_seen(params)

    profile =
      Repo.insert!(%Profile{
        account_id: account.id,
        name: "no-docker",
        platform: :linux,
        vcpus: 2,
        memory_gb: 8,
        docker_cache: false
      })

    WorkflowJob
    |> Repo.get!(job.workflow_job_id)
    |> Ecto.Changeset.change(requested_dispatch_label: Profile.dispatch_label(profile))
    |> Repo.update!()

    assert {:error, :unavailable} = CacheVolumes.allocate_docker(params)

    profile |> Ecto.Changeset.change(docker_cache: true) |> Repo.update!()
    assert {:ok, _} = CacheVolumes.allocate_docker(params)
  end

  test "the account's rollout flag gates the Docker cache", %{params: params} do
    stub(FeatureFlags, :runner_docker_cache_enabled?, fn _ -> false end)
    assert {:error, :unavailable} = CacheVolumes.mark_docker_seen(params)
    assert {:error, :unavailable} = CacheVolumes.allocate_docker(params)
  end

  test "macOS jobs have no Docker data root", %{account: account, job: job, params: params} do
    session(account, job, "mac-pod", :macos)
    assert {:error, :unavailable} = CacheVolumes.mark_docker_seen(%{params | "pod_name" => "mac-pod"})
    assert {:error, :unavailable} = CacheVolumes.allocate_docker(%{params | "pod_name" => "mac-pod"})
  end

  test "the reserved name cannot be requested as a custom volume", %{params: params} do
    assert {:error, :unavailable} = CacheVolumes.allocate(Map.put(params, "key", "docker"))
    assert {:ok, _} = CacheVolumes.allocate(Map.put(params, "key", "docker-images"))
  end

  test "a host that does not hold the data root's size gets nothing", %{params: params} do
    assert :ok = CacheVolumes.mark_docker_seen(params)
    assert {:error, :capacity} = CacheVolumes.allocate_docker(%{params | "max_volume_bytes" => 32_000_000_000})
  end

  describe "reported image inventories" do
    setup %{params: params} do
      :ok = CacheVolumes.mark_docker_seen(params)
      {:ok, docker} = CacheVolumes.allocate_docker(params)
      %{docker: docker}
    end

    test "keeps a well-formed inventory on the use", %{docker: docker} do
      inventory = %{
        "images" => [
          %{
            "id" => @image_id,
            "references" => ["ghcr.io/org/build:jdk-21", "postgres:16"],
            "size_bytes" => 6_000_000_000,
            "last_used_at" => "2026-10-25T10:00:00.123Z"
          }
        ],
        "build_cache_bytes" => 1_000
      }

      assert {:ok, _} = CacheVolumes.report("linux-node", docker.id, report(%{"docker" => inventory}))

      assert %{"images" => [image], "build_cache_bytes" => 1_000} = Repo.get!(Usage, docker.id).docker_images
      assert image["references"] == ["ghcr.io/org/build:jdk-21", "postgres:16"]
      assert image["last_used_at"] == "2026-10-25T10:00:00Z"
    end

    test "drops a malformed inventory", %{docker: docker} do
      inventory = %{"images" => [%{"id" => "../escape", "references" => [], "size_bytes" => 1}], "build_cache_bytes" => 0}
      assert {:ok, _} = CacheVolumes.report("linux-node", docker.id, report(%{"docker" => inventory}))
      assert is_nil(Repo.get!(Usage, docker.id).docker_images)
    end

    test "ignores an inventory reported for any other volume", %{params: params} do
      {:ok, custom} = CacheVolumes.allocate(Map.put(params, "key", "gradle"))
      inventory = %{"images" => [], "build_cache_bytes" => 0}
      assert {:ok, _} = CacheVolumes.report("linux-node", custom.id, report(%{"docker" => inventory}))
      assert is_nil(Repo.get!(Usage, custom.id).docker_images)
    end
  end
end
