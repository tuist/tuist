defmodule Tuist.Runners.ActionsCacheTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query, only: [from: 2]
  import Mimic

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.KeyValueStore
  alias Tuist.Repo
  alias Tuist.Runners.ActionsCache
  alias Tuist.Runners.ActionsCache.Entry
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.Sites
  alias Tuist.Runners.WorkflowJob
  alias Tuist.Storage
  alias Tuist.Storage.S3Target
  alias Tuist.VCS
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @version String.duplicate("a", 64)
  @sha256 String.duplicate("b", 64)
  @store %{
    "site" => "gra",
    "enabled" => true,
    "private_network_ready" => true,
    "endpoint" => "http://shard-storage.kura.svc.cluster.local:3900",
    "bucket" => "shards",
    "actions_cache_bucket" => "actions-cache",
    "actions_cache_bytes" => 100_000_000_000,
    "access_key_id" => "GK0123",
    "secret_access_key" => "secret"
  }

  setup do
    stub(Environment, :runner_cache_volumes_enabled?, fn _ -> true end)
    stub(VCS, :get_github_app_installation_for_account, fn _ -> {:ok, %{installation_id: "99", client_url: nil}} end)

    stub(GitHubClient, :get_repository, fn _, repository ->
      {:ok, %{"id" => 123, "full_name" => repository, "default_branch" => "main"}}
    end)

    stub(KeyValueStore, :get_or_update, fn _key, _opts, func -> func.() end)
    stub(Environment, :shard_storage_targets, fn -> %{"gra-v1" => @store} end)
    stub(Sites, :shard_storage_site, fn _node -> "gra" end)
    stub(Storage, :generate_upload_url, fn _key, _actor, _opts -> "http://store/upload" end)
    stub(Storage, :object_exists?, fn _key, _actor -> true end)
    stub(Storage, :generate_download_url, fn _key, _actor, _opts -> "http://store/download" end)

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

    assert {:ok, _} = ActionsCache.upload(%{"node_name" => "node", "id" => id, "size_bytes" => size, "sha256" => @sha256})
    assert :ok = ActionsCache.commit(%{"node_name" => "node", "id" => id})
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

    test "places a save in the store at the node's site, an account's own storage, or nowhere", ctx do
      pod = running(ctx, "pod-main", push("main"))
      params = %{"pod_name" => pod, "node_name" => "node", "version" => @version}

      {:ok, in_store} = ActionsCache.reserve(Map.merge(params, %{"id" => Ecto.UUID.generate(), "key" => "a"}))
      assert Repo.get(Entry, in_store).storage_target == "gra-v1"

      stub(Sites, :shard_storage_site, fn _node -> "rbx" end)

      assert {:error, :unavailable} =
               ActionsCache.reserve(Map.merge(params, %{"id" => Ecto.UUID.generate(), "key" => "b"}))

      Repo.update_all(from(a in Account, where: a.id == ^ctx.account.id),
        set: [s3_bucket_name: "own", s3_access_key_id: "key", s3_secret_access_key: "secret"]
      )

      {:ok, own} = ActionsCache.reserve(Map.merge(params, %{"id" => Ecto.UUID.generate(), "key" => "c"}))
      assert Repo.get(Entry, own).storage_target == nil
    end
  end

  describe "upload/1 and commit/1" do
    test "signs an upload into the store bound to the digest, and restores only what the store holds",
         %{account: account} = ctx do
      pod = running(ctx, "pod-main", push("main"))
      id = Ecto.UUID.generate()

      {:ok, ^id} =
        ActionsCache.reserve(%{
          "pod_name" => pod,
          "node_name" => "node",
          "id" => id,
          "key" => "deps",
          "version" => @version
        })

      upload = %{"node_name" => "node", "id" => id, "size_bytes" => 10, "sha256" => @sha256}
      assert {:error, :not_found} = ActionsCache.upload(%{upload | "node_name" => "other"})
      assert {:error, :unavailable} = ActionsCache.upload(%{upload | "size_bytes" => 6_000_000_000})

      expect(Storage, :generate_upload_url, fn key, %S3Target{id: "gra-v1", bucket: "actions-cache"}, opts ->
        assert key == "runner-actions-cache/#{account.id}/123/" <> id
        assert [{"x-amz-checksum-sha256", _}] = opts[:signed_headers]
        "http://store/upload"
      end)

      assert {:ok, %{upload_url: "http://store/upload", checksum: checksum}} = ActionsCache.upload(upload)
      assert checksum == @sha256 |> Base.decode16!(case: :lower) |> Base.encode64()

      lookup = %{"pod_name" => pod, "node_name" => "node", "key" => "deps", "version" => @version}
      stub(Storage, :object_exists?, fn _key, _actor -> false end)
      assert {:error, :unavailable} = ActionsCache.commit(%{"node_name" => "node", "id" => id})
      assert {:ok, nil} = ActionsCache.lookup(lookup)

      stub(Storage, :object_exists?, fn _key, %S3Target{bucket: "actions-cache"} -> true end)
      assert :ok = ActionsCache.commit(%{"node_name" => "node", "id" => id})
      assert :ok = ActionsCache.commit(%{"node_name" => "node", "id" => id})
      assert {:ok, %{id: ^id, size_bytes: 10, download_url: "http://store/download"}} = ActionsCache.lookup(lookup)
      assert {:error, :not_found} = ActionsCache.upload(upload)
    end

    test "a host at another site misses an entry rather than read a store it cannot reach", ctx do
      pod = running(ctx, "pod-main", push("main"))
      save(pod, "deps")
      stub(Sites, :shard_storage_site, fn _node -> "rbx" end)

      assert restore(pod, "deps") == nil
    end

    test "an account's own storage gets public links only", ctx do
      Repo.update_all(from(a in Account, where: a.id == ^ctx.account.id),
        set: [s3_bucket_name: "own", s3_access_key_id: "key", s3_secret_access_key: "secret"]
      )

      stub(Storage, :generate_download_url, fn _key, %Account{}, _opts -> "http://10.0.0.1/download" end)
      pod = running(ctx, "pod-main", push("main"))
      save(pod, "deps")

      assert restore(pod, "deps") == nil
    end
  end

  describe "sweep/1" do
    test "deletes abandoned reservations, idle entries and a repository's oldest entries beyond its limit",
         %{account: account} = ctx do
      pod = running(ctx, "pod-main", push("main"))
      now = DateTime.utc_now()

      idle = save(pod, "idle")
      oldest = save(pod, "oldest", min(30_000_000_000, 5_000_000_000))
      Repo.update_all(from(e in Entry, where: e.id == ^oldest), set: [size_bytes: 30_000_000_000])
      newest = save(pod, "newest", 5_000_000_000)
      Repo.update_all(from(e in Entry, where: e.id == ^newest), set: [size_bytes: 30_000_000_000])

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

      expect(Storage, :delete_objects, fn keys, %S3Target{bucket: "actions-cache"} ->
        assert Enum.sort(keys) ==
                 Enum.sort(for id <- [idle, oldest, abandoned], do: "runner-actions-cache/#{account.id}/123/#{id}")

        :ok
      end)

      assert {:ok, 3} = ActionsCache.sweep(now)
      assert Enum.map(Repo.all(Entry), & &1.id) == [newest]
    end

    test "keeps a store under 90% of its quota, least recently used first", ctx do
      stub(Environment, :shard_storage_targets, fn -> %{"gra-v1" => %{@store | "actions_cache_bytes" => 100}} end)
      pod = running(ctx, "pod-main", push("main"))
      now = DateTime.utc_now()
      old = save(pod, "old", 40)
      recent = save(pod, "recent", 40)
      newest = save(pod, "newest", 40)

      for {id, hours} <- [{old, -3}, {recent, -2}, {newest, -1}] do
        Repo.update_all(from(e in Entry, where: e.id == ^id), set: [last_used_at: DateTime.add(now, hours, :hour)])
      end

      stub(Storage, :delete_objects, fn _keys, _actor -> :ok end)

      assert {:ok, 1} = ActionsCache.sweep(now)
      refute Repo.get(Entry, old)
      assert Repo.get(Entry, recent) && Repo.get(Entry, newest)
    end

    test "keeps an entry whose object could not be deleted, and drops one whose store is gone", ctx do
      pod = running(ctx, "pod-main", push("main"))
      id = save(pod, "idle")
      now = DateTime.utc_now()
      Repo.update_all(Entry, set: [last_used_at: DateTime.add(now, -8, :day)])
      stub(Storage, :delete_objects, fn _, _ -> {:error, :unavailable} end)

      assert {:ok, 0} = ActionsCache.sweep(now)
      assert Repo.get(Entry, id)

      stub(Environment, :shard_storage_targets, fn -> %{} end)
      assert {:ok, 1} = ActionsCache.sweep(now)
    end
  end
end
