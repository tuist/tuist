defmodule Tuist.Runners.DispatchTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.Accounts
  alias Tuist.Kubernetes.Client
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Dispatch
  alias Tuist.Runners.Jobs
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :verify_on_exit!

  setup do
    cache = :"runners_dispatch_#{System.unique_integer([:positive])}"
    start_supervised!({Cachex, name: cache})
    stub(Dispatch, :cache_name, fn -> cache end)
    :ok
  end

  defp account_with_cap(cap) do
    account = AccountsFixtures.organization_fixture().account

    account
    |> Ecto.Changeset.change(runner_max_concurrent: cap)
    |> Tuist.Repo.update!()
  end

  defp queued_payload(opts) do
    owner = Keyword.get(opts, :owner, "tuist")
    labels = Keyword.get(opts, :labels, ["tuist-macos"])

    %{
      "action" => "queued",
      "workflow_job" => %{
        "id" => System.unique_integer([:positive]),
        "labels" => labels,
        "run_id" => 1,
        "run_attempt" => 1,
        "name" => "Build",
        "head_branch" => "main",
        "head_sha" => "abc"
      },
      "repository" => %{"full_name" => "#{owner}/repo"}
    }
  end

  defp pool_cr(opts) do
    %{
      "metadata" => %{"name" => Keyword.fetch!(opts, :name)},
      "spec" => %{"dispatchLabel" => Keyword.fetch!(opts, :label)}
    }
  end

  defp completed_payload(opts) do
    %{
      "action" => "completed",
      "workflow_job" => %{
        "id" => Keyword.get(opts, :id, System.unique_integer([:positive])),
        "conclusion" => Keyword.get(opts, :conclusion, "success"),
        "steps" => Keyword.get(opts, :steps, [])
      },
      "repository" => %{"full_name" => "tuist/repo"}
    }
  end

  describe "handle_webhook/2" do
    test "returns {:ignored, :no_account} when the org login doesn't match a Tuist account" do
      stub(Accounts, :get_account_by_handle, fn _ -> nil end)

      assert {:ignored, :no_account} =
               Dispatch.handle_webhook(queued_payload(owner: "ghost"), 1)
    end

    test "returns {:ignored, :runners_disabled} when the account has runner_max_concurrent=0" do
      account = account_with_cap(0)

      stub(Accounts, :get_account_by_handle, fn _ -> account end)

      assert {:ignored, :runners_disabled} =
               Dispatch.handle_webhook(queued_payload(owner: account.name), 1)
    end

    test "returns {:ignored, :no_matching_pool} when none of the pools' dispatchLabels match" do
      account = account_with_cap(5)

      stub(Accounts, :get_account_by_handle, fn _ -> account end)

      stub(Client, :list_runner_pools, fn _ns ->
        {:ok, [pool_cr(name: "default", label: "tuist-linux")]}
      end)

      payload = queued_payload(owner: account.name, labels: ["tuist-macos"])
      assert {:ignored, :no_matching_pool} = Dispatch.handle_webhook(payload, 1)
    end

    test "returns {:ignored, :no_pools} when the cluster has no RunnerPool CRs" do
      account = account_with_cap(5)

      stub(Accounts, :get_account_by_handle, fn _ -> account end)
      stub(Client, :list_runner_pools, fn _ns -> {:ok, []} end)

      assert {:ignored, :no_pools} =
               Dispatch.handle_webhook(queued_payload(owner: account.name), 1)
    end

    test "caches enabled accounts across two webhook calls within the TTL" do
      account = account_with_cap(5)

      expect(Accounts, :get_account_by_handle, 1, fn _ -> account end)
      stub(Client, :list_runner_pools, fn _ns -> {:ok, []} end)

      payload = queued_payload(owner: account.name)

      assert {:ignored, :no_pools} = Dispatch.handle_webhook(payload, 1)
      assert {:ignored, :no_pools} = Dispatch.handle_webhook(payload, 1)
    end

    test "does NOT cache cap=0 accounts so adoption (flip from disabled to enabled) takes effect immediately" do
      account = account_with_cap(0)

      expect(Accounts, :get_account_by_handle, 2, fn _ -> account end)

      payload = queued_payload(owner: account.name)

      assert {:ignored, :runners_disabled} = Dispatch.handle_webhook(payload, 1)
      assert {:ignored, :runners_disabled} = Dispatch.handle_webhook(payload, 1)
    end
  end

  describe "handle_webhook/2 completed" do
    test "sanitises the workflow_job steps and forwards them to Jobs.complete" do
      test_pid = self()
      stub(Claims, :complete, fn _ -> :ok end)

      stub(Jobs, :complete, fn _id, conclusion, steps ->
        send(test_pid, {:completed, conclusion, steps})
        {:ok, %{}}
      end)

      payload =
        completed_payload(
          id: 4242,
          conclusion: "success",
          steps: [
            %{
              "name" => "Set up job",
              "status" => "completed",
              "conclusion" => "success",
              "number" => 1,
              "started_at" => "2026-05-28T10:00:00Z",
              "completed_at" => "2026-05-28T10:00:05Z"
            },
            # A nameless entry is dropped rather than stored half-formed.
            %{"status" => "completed"}
          ]
        )

      assert {:ok, :completed} = Dispatch.handle_webhook(payload, 1)

      assert_receive {:completed, "success", steps_json}

      assert [
               %{
                 "name" => "Set up job",
                 "status" => "completed",
                 "conclusion" => "success",
                 "number" => 1,
                 "started_at" => "2026-05-28T10:00:00Z",
                 "completed_at" => "2026-05-28T10:00:05Z"
               }
             ] = JSON.decode!(steps_json)
    end

    test "forwards an empty steps payload as a blank string" do
      test_pid = self()
      stub(Claims, :complete, fn _ -> :ok end)

      stub(Jobs, :complete, fn _id, _conclusion, steps ->
        send(test_pid, {:steps, steps})
        {:ok, %{}}
      end)

      assert {:ok, :completed} = Dispatch.handle_webhook(completed_payload(steps: []), 1)

      assert_receive {:steps, ""}
    end
  end

  describe "match_pool/1" do
    test "returns the pool whose dispatchLabel matches one of the requested labels" do
      stub(Client, :list_runner_pools, fn _ns ->
        {:ok,
         [
           %{
             "metadata" => %{"name" => "macos-pool"},
             "spec" => %{
               "dispatchLabel" => "tuist-macos",
               "runnerLabels" => ["self-hosted", "macOS", "ARM64"]
             }
           },
           %{
             "metadata" => %{"name" => "linux-pool"},
             "spec" => %{
               "dispatchLabel" => "tuist-linux",
               "runnerLabels" => ["self-hosted", "Linux", "X64"]
             }
           }
         ]}
      end)

      assert {:ok,
              %{
                name: "linux-pool",
                dispatch_label: "tuist-linux",
                runner_labels: ["self-hosted", "Linux", "X64"]
              }} = Dispatch.match_pool(["self-hosted", "tuist-linux"])
    end

    test "returns :no_matching_pool when no dispatchLabel intersects" do
      stub(Client, :list_runner_pools, fn _ns ->
        {:ok,
         [
           %{
             "metadata" => %{"name" => "macos-pool"},
             "spec" => %{"dispatchLabel" => "tuist-macos"}
           }
         ]}
      end)

      assert {:error, :no_matching_pool} = Dispatch.match_pool(["ubuntu-latest"])
    end

    test "returns :no_pools when no RunnerPool CRs exist" do
      stub(Client, :list_runner_pools, fn _ns -> {:ok, []} end)

      assert {:error, :no_pools} = Dispatch.match_pool(["tuist-macos"])
    end

    test "caches the K8s LIST result across calls within the TTL" do
      pool = pool_cr(name: "default", label: "tuist-linux")
      expect(Client, :list_runner_pools, 1, fn _ns -> {:ok, [pool]} end)

      assert {:error, :no_matching_pool} = Dispatch.match_pool(["tuist-macos"])
      assert {:error, :no_matching_pool} = Dispatch.match_pool(["tuist-macos"])
    end

    test "does NOT cache K8s LIST errors so a transient apiserver hiccup recovers" do
      expect(Client, :list_runner_pools, 2, fn _ns -> {:error, :unreachable} end)

      assert {:error, :no_pools} = Dispatch.match_pool(["tuist-macos"])
      assert {:error, :no_pools} = Dispatch.match_pool(["tuist-macos"])
    end
  end

  describe "pool_summary_by_name/1" do
    test "returns name + dispatch_label + runner_labels from the CR" do
      stub(Client, :get_runner_pool, fn _ns, "linux-pool" ->
        {:ok,
         %{
           "metadata" => %{"name" => "linux-pool"},
           "spec" => %{
             "dispatchLabel" => "tuist-linux-ubuntu-22-04",
             "runnerLabels" => ["self-hosted", "Linux", "X64"]
           }
         }}
      end)

      assert {:ok,
              %{
                name: "linux-pool",
                dispatch_label: "tuist-linux-ubuntu-22-04",
                runner_labels: ["self-hosted", "Linux", "X64"]
              }} = Dispatch.pool_summary_by_name("linux-pool")
    end

    test "returns [] when runnerLabels is absent" do
      stub(Client, :get_runner_pool, fn _ns, "macos-pool" ->
        {:ok,
         %{
           "metadata" => %{"name" => "macos-pool"},
           "spec" => %{"dispatchLabel" => "tuist-macos"}
         }}
      end)

      assert {:ok, %{runner_labels: []}} = Dispatch.pool_summary_by_name("macos-pool")
    end

    test "returns [] when runnerLabels is empty" do
      stub(Client, :get_runner_pool, fn _ns, "macos-pool" ->
        {:ok,
         %{
           "metadata" => %{"name" => "macos-pool"},
           "spec" => %{"dispatchLabel" => "tuist-macos", "runnerLabels" => []}
         }}
      end)

      assert {:ok, %{runner_labels: []}} = Dispatch.pool_summary_by_name("macos-pool")
    end

    test "filters non-string and empty entries from runnerLabels" do
      stub(Client, :get_runner_pool, fn _ns, "mixed-pool" ->
        {:ok,
         %{
           "metadata" => %{"name" => "mixed-pool"},
           "spec" => %{
             "dispatchLabel" => "tuist-mixed",
             "runnerLabels" => ["self-hosted", "", nil, "Linux", "X64"]
           }
         }}
      end)

      assert {:ok, %{runner_labels: ["self-hosted", "Linux", "X64"]}} =
               Dispatch.pool_summary_by_name("mixed-pool")
    end

    test "returns :no_dispatch_label when the CR has no dispatchLabel" do
      stub(Client, :get_runner_pool, fn _ns, "broken-pool" ->
        {:ok, %{"metadata" => %{"name" => "broken-pool"}, "spec" => %{}}}
      end)

      assert {:error, :no_dispatch_label} = Dispatch.pool_summary_by_name("broken-pool")
    end

    test "propagates K8s client errors" do
      stub(Client, :get_runner_pool, fn _ns, _name -> {:error, :not_found} end)

      assert {:error, :not_found} = Dispatch.pool_summary_by_name("missing-pool")
    end
  end
end
