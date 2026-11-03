defmodule Tuist.Runners.ActionsCacheTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query, only: [from: 2]
  import Mimic

  alias Tuist.Environment
  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.KeyValueStore
  alias Tuist.Repo
  alias Tuist.Runners.ActionsCache
  alias Tuist.Runners.ActionsCache.Entry
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.WorkflowJob
  alias Tuist.Storage
  alias Tuist.VCS
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @version String.duplicate("a", 64)
  @sha256 String.duplicate("b", 64)

  setup do
    stub(Environment, :runner_cache_volumes_enabled?, fn _ -> true end)
    stub(VCS, :get_github_app_installation_for_account, fn _ -> {:ok, %{installation_id: "99", client_url: nil}} end)

    stub(GitHubClient, :get_repository, fn _, repository ->
      {:ok, %{"id" => 123, "full_name" => repository, "default_branch" => "main"}}
    end)

    stub(KeyValueStore, :get_or_update, fn _key, _opts, func -> func.() end)

    runs = start_supervised!({Agent, fn -> %{} end})
    stub(GitHubClient, :get_workflow_run, fn %{run_id: id} -> {:ok, Agent.get(runs, &Map.fetch!(&1, id))} end)

    %{account: AccountsFixtures.account_fixture(), runs: runs}
  end

  # A running job on `pod` whose workflow run GitHub reports as `run`.
  defp running(%{account: account, runs: runs}, pod, run) do
    run_id = System.unique_integer([:positive])
    job_id = System.unique_integer([:positive])

    Repo.insert!(%WorkflowJob{
      workflow_job_id: job_id,
      account_id: account.id,
      provider: "github",
      status: "running",
      fleet_name: "linux",
      repository: "org/repo",
      workflow_run_id: run_id,
      run_attempt: 1,
      enqueued_at: DateTime.utc_now()
    })

    Repo.insert!(%RunnerSession{
      account_id: account.id,
      workflow_job_id: job_id,
      executed_workflow_job_id: job_id,
      fleet_name: "linux",
      pod_name: pod,
      node_name: "node",
      platform: :linux,
      vcpus: 2,
      memory_gb: 8,
      billing_multiplier: 10_000,
      started_at: DateTime.utc_now()
    })

    run = Map.merge(%{"id" => run_id, "run_attempt" => 1, "repository" => %{"id" => 123}}, run)
    Agent.update(runs, &Map.put(&1, run_id, run))
    pod
  end

  defp push(branch), do: %{"event" => "push", "head_branch" => branch, "head_repository" => %{"id" => 123}}

  defp pull_request(number, branch, base) do
    %{
      "event" => "pull_request",
      "head_branch" => branch,
      "head_repository" => %{"id" => 123},
      "pull_requests" => [%{"number" => number, "head" => %{"repo" => %{"id" => 123}}, "base" => %{"ref" => base}}]
    }
  end

  defp save(pod, key, size \\ 10) do
    id = Ecto.UUID.generate()

    assert {:ok, ^id} =
             ActionsCache.reserve(%{
               "pod_name" => pod,
               "node_name" => "node",
               "id" => id,
               "key" => key,
               "version" => @version
             })

    assert {:ok, _} = ActionsCache.commit(%{"node_name" => "node", "id" => id, "size_bytes" => size, "sha256" => @sha256})
    id
  end

  defp restore(pod, key, restore_keys \\ []) do
    {:ok, entry} =
      ActionsCache.lookup(%{
        "pod_name" => pod,
        "node_name" => "node",
        "key" => key,
        "restore_keys" => restore_keys,
        "version" => @version
      })

    entry && entry.key
  end

  describe "github_scope/2" do
    setup do
      %{job: %{account_id: 1, repository: "org/repo", workflow_run_id: 5, run_attempt: 1}}
    end

    defp run(job, attrs) do
      Map.merge(
        %{
          "id" => job.workflow_run_id,
          "run_attempt" => 1,
          "repository" => %{"id" => 123, "full_name" => "org/repo", "default_branch" => "main"}
        },
        attrs
      )
    end

    test "a pull request saves under its merge ref and restores from its base and the default branch", %{job: job} do
      assert {:ok, %{write: "refs/pull/7/merge", read: ["refs/pull/7/merge", "refs/heads/release", "refs/heads/main"]}} =
               ActionsCache.github_scope(job, run(job, pull_request(7, "feature", "release")))
    end

    test "a push saves under its branch", %{job: job} do
      assert {:ok, %{write: "refs/heads/feature", read: ["refs/heads/feature", "refs/heads/main"]}} =
               ActionsCache.github_scope(job, run(job, push("feature")))

      assert {:ok, %{write: "refs/heads/main", read: ["refs/heads/main"]}} =
               ActionsCache.github_scope(job, run(job, push("main")))
    end

    test "a fork saves under its own branch only", %{job: job} do
      attrs = %{
        "event" => "pull_request",
        "head_branch" => "main",
        "head_repository" => %{"id" => 999},
        "pull_requests" => []
      }

      assert {:ok, %{write: "fork/999/main", read: ["fork/999/main", "refs/heads/main"]}} =
               ActionsCache.github_scope(job, run(job, attrs))
    end

    test "a run that is not the job's is refused", %{job: job} do
      assert {:error, :unavailable} = ActionsCache.github_scope(job, run(job, Map.put(push("main"), "run_attempt", 2)))
    end
  end

  describe "lookup/1" do
    test "restores an exact key, then a key prefix, then restore keys, newest first", ctx do
      pod = running(ctx, "pod-main", push("main"))
      save(pod, "deps-linux-abc")
      save(pod, "deps-linux-def")

      assert restore(pod, "deps-linux-abc") == "deps-linux-abc"
      assert restore(pod, "deps-linux") == "deps-linux-def"
      assert restore(pod, "deps-mac", ["deps-"]) == "deps-linux-def"
      assert restore(pod, "deps-mac", ["other-"]) == nil
    end

    test "treats LIKE wildcards in keys literally", ctx do
      pod = running(ctx, "pod-main", push("main"))
      save(pod, "deps-linux")

      assert restore(pod, "deps_") == nil
      assert restore(pod, "%") == nil
    end

    test "a branch restores its own entries before the default branch's and never another branch's",
         ctx do
      main = running(ctx, "pod-main", push("main"))
      save(main, "deps-main")
      other = running(ctx, "pod-other", push("other"))
      save(other, "deps-other")
      feature = running(ctx, "pod-feature", push("feature"))

      assert restore(feature, "deps-", []) == "deps-main"
      save(feature, "deps-feature")
      assert restore(feature, "deps-") == "deps-feature"
      assert restore(main, "deps-") == "deps-main"
    end

    test "a pull request restores from its base branch", ctx do
      release = running(ctx, "pod-release", push("release"))
      save(release, "deps-release")
      pr = running(ctx, "pod-pr", pull_request(7, "feature", "release"))

      assert restore(pr, "deps-") == "deps-release"
    end

    test "an uncommitted reservation is not restored", ctx do
      pod = running(ctx, "pod-main", push("main"))

      {:ok, _} =
        ActionsCache.reserve(%{
          "pod_name" => pod,
          "node_name" => "node",
          "id" => Ecto.UUID.generate(),
          "key" => "deps",
          "version" => @version
        })

      assert restore(pod, "deps") == nil
    end

    test "a pod with no executed job is pending", %{account: account} do
      Repo.insert!(%RunnerSession{
        account_id: account.id,
        workflow_job_id: System.unique_integer([:positive]),
        fleet_name: "linux",
        pod_name: "pod-pending",
        node_name: "node",
        platform: :linux,
        vcpus: 2,
        memory_gb: 8,
        billing_multiplier: 10_000,
        started_at: DateTime.utc_now()
      })

      assert {:error, :pending} =
               ActionsCache.lookup(%{
                 "pod_name" => "pod-pending",
                 "node_name" => "node",
                 "key" => "k",
                 "version" => @version
               })
    end

    test "an unknown pod is unavailable" do
      assert {:error, :unavailable} =
               ActionsCache.lookup(%{"pod_name" => "nobody", "node_name" => "node", "key" => "k", "version" => @version})
    end
  end

  describe "reserve/1" do
    test "refuses a key and version the scope already holds, and repeats its own reservation",
         ctx do
      pod = running(ctx, "pod-main", push("main"))
      id = save(pod, "deps")
      params = %{"pod_name" => pod, "node_name" => "node", "key" => "deps", "version" => @version}

      assert {:error, :conflict} = ActionsCache.reserve(Map.put(params, "id", Ecto.UUID.generate()))
      assert {:ok, ^id} = ActionsCache.reserve(Map.put(params, "id", id))
    end

    test "replaces a reservation abandoned for over an hour", ctx do
      pod = running(ctx, "pod-main", push("main"))
      params = %{"pod_name" => pod, "node_name" => "node", "key" => "deps", "version" => @version}
      first = Ecto.UUID.generate()
      {:ok, ^first} = ActionsCache.reserve(Map.put(params, "id", first))
      second = Ecto.UUID.generate()

      assert {:error, :conflict} = ActionsCache.reserve(Map.put(params, "id", second))

      Repo.update_all(Entry, set: [inserted_at: DateTime.add(DateTime.utc_now(), -2, :hour)])

      assert {:ok, ^second} = ActionsCache.reserve(Map.put(params, "id", second))
      refute Repo.get(Entry, first)
    end
  end

  describe "commit/1 and stored/1" do
    test "signs a storage upload once and serves the stored copy", %{account: account} = ctx do
      stub(Storage, :supports_signed_upload_headers?, fn _ -> true end)
      id = Ecto.UUID.generate()

      expect(Storage, :generate_upload_url, fn key, _account, opts ->
        assert key == "runner-actions-cache/#{account.id}/123/" <> id
        assert [{"x-amz-checksum-sha256", _}] = opts[:signed_headers]
        "https://storage.example.com/upload"
      end)

      stub(Storage, :generate_download_url, fn _key, _account, _opts -> "https://storage.example.com/download" end)

      pod = running(ctx, "pod-main", push("main"))

      {:ok, ^id} =
        ActionsCache.reserve(%{
          "pod_name" => pod,
          "node_name" => "node",
          "id" => id,
          "key" => "deps",
          "version" => @version
        })

      assert {:error, :not_found} =
               ActionsCache.commit(%{"node_name" => "other", "id" => id, "size_bytes" => 10, "sha256" => @sha256})

      assert {:ok, %{upload_url: "https://storage.example.com/upload", checksum: checksum}} =
               ActionsCache.commit(%{"node_name" => "node", "id" => id, "size_bytes" => 10, "sha256" => @sha256})

      assert checksum == @sha256 |> Base.decode16!(case: :lower) |> Base.encode64()

      lookup = %{"pod_name" => pod, "node_name" => "node", "key" => "deps", "version" => @version}
      assert {:ok, %{id: ^id, size_bytes: 10, download_url: nil}} = ActionsCache.lookup(lookup)

      assert :ok = ActionsCache.stored(%{"node_name" => "node", "id" => id})
      assert {:ok, %{download_url: "https://storage.example.com/download"}} = ActionsCache.lookup(lookup)

      assert {:error, :conflict} =
               ActionsCache.commit(%{"node_name" => "node", "id" => id, "size_bytes" => 11, "sha256" => @sha256})
    end

    test "keeps entries larger than one upload on their host", ctx do
      reject(&Storage.generate_upload_url/3)
      pod = running(ctx, "pod-main", push("main"))
      id = Ecto.UUID.generate()

      {:ok, ^id} =
        ActionsCache.reserve(%{
          "pod_name" => pod,
          "node_name" => "node",
          "id" => id,
          "key" => "big",
          "version" => @version
        })

      assert {:ok, %{upload_url: nil}} =
               ActionsCache.commit(%{
                 "node_name" => "node",
                 "id" => id,
                 "size_bytes" => 6_000_000_000,
                 "sha256" => @sha256
               })
    end
  end

  describe "sweep/1" do
    test "deletes abandoned reservations, idle entries and a repository's oldest entries beyond its limit",
         %{
           account: account
         } = ctx do
      stub(Storage, :generate_upload_url, fn _, _, _ -> nil end)
      pod = running(ctx, "pod-main", push("main"))
      now = DateTime.utc_now()

      idle = save(pod, "idle")
      oldest = save(pod, "oldest", 30_000_000_000)
      newest = save(pod, "newest", 30_000_000_000)

      {:ok, abandoned} =
        ActionsCache.reserve(%{
          "pod_name" => pod,
          "node_name" => "node",
          "id" => Ecto.UUID.generate(),
          "key" => "abandoned",
          "version" => @version
        })

      Repo.update_all(from(e in Entry, where: e.id == ^idle), set: [last_used_at: DateTime.add(now, -8, :day)])
      Repo.update_all(from(e in Entry, where: e.id == ^oldest), set: [last_used_at: DateTime.add(now, -1, :day)])
      Repo.update_all(from(e in Entry, where: e.id == ^abandoned), set: [inserted_at: DateTime.add(now, -2, :hour)])
      Repo.update_all(from(e in Entry, where: e.id == ^oldest), set: [stored_at: now])

      expect(Storage, :delete_objects, fn [key], _account ->
        assert key == "runner-actions-cache/#{account.id}/123/#{oldest}"
        :ok
      end)

      assert {:ok, 3} = ActionsCache.sweep(now)
      assert Enum.map(Repo.all(Entry), & &1.id) == [newest]
    end

    test "keeps a stored entry whose object could not be deleted", ctx do
      stub(Storage, :generate_upload_url, fn _, _, _ -> nil end)
      pod = running(ctx, "pod-main", push("main"))
      id = save(pod, "idle")
      now = DateTime.utc_now()
      Repo.update_all(Entry, set: [last_used_at: DateTime.add(now, -8, :day), stored_at: now])
      stub(Storage, :delete_objects, fn _, _ -> {:error, :unavailable} end)

      assert {:ok, 0} = ActionsCache.sweep(now)
      assert Repo.get(Entry, id)
    end
  end
end
