defmodule Tuist.Runners.DispatchTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.Accounts
  alias Tuist.FeatureFlags
  alias Tuist.Kubernetes.Client
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Dispatch
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.JobSteps
  alias Tuist.Runners.Profiles
  alias Tuist.Runners.RunnerSessions
  alias Tuist.VCS
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :verify_on_exit!

  setup do
    cache = :"runners_dispatch_#{System.unique_integer([:positive])}"
    start_supervised!({Cachex, name: cache})
    stub(Dispatch, :cache_name, fn -> cache end)

    # Default: no installation row for the webhook's installation_id, so
    # resolution falls back to the legacy `owner == account.name`
    # convention the bulk of these cases exercise. The installation-first
    # path has its own case that overrides this stub.
    stub(VCS, :get_github_app_installation_by_installation_id, fn _ -> {:error, :not_found} end)

    # Disable the macOS protected-profile auto-bootstrap globally for
    # this suite. `Accounts.create_organization` and `Accounts.create_user`
    # auto-create a `macos` profile when the macOS catalog has a
    # default Xcode + shape; with `default_xcode_version/0 -> nil`
    # the bootstrap short-circuits to `{:ok, :no_macos_capable}` and
    # the resulting accounts only carry the `linux` protected
    # profile. Test cases that care about a macOS profile add their
    # own per-account inserts. (Stubbing Linux is unnecessary — the
    # `linux` bootstrap reads the test-config default shape.)
    stub(Catalog, :default_xcode_version, fn -> nil end)
    :ok
  end

  defp enabled_account do
    AccountsFixtures.organization_fixture().account
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
    job =
      maybe_put(
        %{
          "id" => Keyword.get(opts, :id, System.unique_integer([:positive])),
          "conclusion" => Keyword.get(opts, :conclusion, "success"),
          "steps" => Keyword.get(opts, :steps, [])
        },
        "runner_name",
        Keyword.get(opts, :runner_name)
      )

    %{
      "action" => "completed",
      "workflow_job" => job,
      "repository" => %{"full_name" => "tuist/repo"}
    }
  end

  defp in_progress_payload(opts) do
    %{
      "action" => "in_progress",
      "workflow_job" =>
        maybe_put(
          %{"id" => Keyword.get(opts, :id, System.unique_integer([:positive]))},
          "runner_name",
          Keyword.get(opts, :runner_name)
        ),
      "repository" => %{"full_name" => "tuist/repo"}
    }
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  describe "handle_webhook/2" do
    test "returns {:ignored, :no_account} when neither the installation nor the org login match a Tuist account" do
      stub(Accounts, :get_account_by_handle, fn _ -> nil end)

      assert {:ignored, :no_account} =
               Dispatch.handle_webhook(queued_payload(owner: "ghost"), 1)
    end

    test "resolves the account via the installation even when the org login doesn't match the handle" do
      account = enabled_account()

      # The customer's GitHub org login differs from their Tuist handle,
      # so the legacy name convention can't find them — but the App
      # installation maps straight to the account.
      stub(Accounts, :get_account_by_handle, fn _ -> nil end)
      stub(VCS, :get_github_app_installation_by_installation_id, fn 123_975_483 -> {:ok, %{account_id: account.id}} end)

      stub(Client, :list_runner_pools, fn _ns ->
        {:ok, [pool_cr(name: "macos-pool", label: "tuist-macos")]}
      end)

      payload = queued_payload(owner: "DigitalSolutionsPest", labels: ["tuist-macos"])

      assert {:ok, :queued} = Dispatch.handle_webhook(payload, 123_975_483)

      counts = Jobs.status_counts(account.id)
      assert Map.get(counts, "queued", 0) == 1
    end

    test "prefers the installation-resolved account over the handle match" do
      installation_account = enabled_account()

      # A different account happens to share the org login; the
      # installation link is authoritative, so we must dispatch against
      # the account that actually connected the App.
      stub(Accounts, :get_account_by_handle, fn _ -> enabled_account() end)

      stub(VCS, :get_github_app_installation_by_installation_id, fn _ ->
        {:ok, %{account_id: installation_account.id}}
      end)

      stub(Client, :list_runner_pools, fn _ns ->
        {:ok, [pool_cr(name: "macos-pool", label: "tuist-macos")]}
      end)

      payload = queued_payload(owner: "shared-login", labels: ["tuist-macos"])

      assert {:ok, :queued} = Dispatch.handle_webhook(payload, 555)

      assert Map.get(Jobs.status_counts(installation_account.id), "queued", 0) == 1
    end

    test "returns {:ignored, :runners_disabled} when runners aren't enabled for the account" do
      account = enabled_account()

      stub(Accounts, :get_account_by_handle, fn _ -> account end)
      stub(FeatureFlags, :runners_enabled?, fn _ -> false end)

      assert {:ignored, :runners_disabled} =
               Dispatch.handle_webhook(queued_payload(owner: account.name), 1)
    end

    test "returns {:ignored, :no_matching_pool} when none of the pools' dispatchLabels match" do
      account = enabled_account()

      stub(Accounts, :get_account_by_handle, fn _ -> account end)

      stub(Client, :list_runner_pools, fn _ns ->
        {:ok, [pool_cr(name: "default", label: "tuist-linux")]}
      end)

      payload = queued_payload(owner: account.name, labels: ["tuist-macos"])
      assert {:ignored, :no_matching_pool} = Dispatch.handle_webhook(payload, 1)
    end

    test "enqueues waiting self-hosted jobs as queued work" do
      account = enabled_account()

      stub(Accounts, :get_account_by_handle, fn _ -> account end)

      stub(Client, :list_runner_pools, fn _ns ->
        {:ok, [pool_cr(name: "macos-pool", label: "tuist-macos")]}
      end)

      payload =
        [owner: account.name, labels: ["self-hosted", "tuist-macos"]]
        |> queued_payload()
        |> Map.put("action", "waiting")

      assert {:ok, :queued} = Dispatch.handle_webhook(payload, 1)

      counts = Jobs.status_counts(account.id)
      assert Map.get(counts, "queued", 0) == 1
    end

    test "returns {:ignored, :no_pools} when the cluster has no RunnerPool CRs" do
      account = enabled_account()

      stub(Accounts, :get_account_by_handle, fn _ -> account end)
      stub(Client, :list_runner_pools, fn _ns -> {:ok, []} end)

      assert {:ignored, :no_pools} =
               Dispatch.handle_webhook(queued_payload(owner: account.name), 1)
    end

    test "caches the account lookup across two webhook calls within the TTL" do
      account = enabled_account()

      expect(Accounts, :get_account_by_handle, 1, fn _ -> account end)
      stub(Client, :list_runner_pools, fn _ns -> {:ok, []} end)

      payload = queued_payload(owner: account.name)

      assert {:ignored, :no_pools} = Dispatch.handle_webhook(payload, 1)
      assert {:ignored, :no_pools} = Dispatch.handle_webhook(payload, 1)
    end

    test "a flag flip from disabled to enabled takes effect on the next webhook" do
      account = enabled_account()

      # The account is fetched once and cached; enablement is
      # re-evaluated per webhook, so flipping the flag on is reflected
      # on the very next delivery without waiting out the cache TTL.
      expect(Accounts, :get_account_by_handle, 1, fn _ -> account end)

      FeatureFlags
      |> expect(:runners_enabled?, fn _ -> false end)
      |> expect(:runners_enabled?, fn _ -> true end)

      stub(Client, :list_runner_pools, fn _ns -> {:ok, []} end)

      payload = queued_payload(owner: account.name)

      assert {:ignored, :runners_disabled} = Dispatch.handle_webhook(payload, 1)
      assert {:ignored, :no_pools} = Dispatch.handle_webhook(payload, 1)
    end
  end

  describe "handle_webhook/2 completed" do
    test "writes the workflow_job steps to runner_job_steps and skips nameless entries" do
      test_pid = self()
      stub(Claims, :complete, fn _ -> :ok end)

      stub(Jobs, :complete, fn _id, conclusion ->
        send(test_pid, {:completed, conclusion})
        {:ok, %{account_id: 777}}
      end)

      stub(JobSteps, :record, fn rows ->
        send(test_pid, {:steps, rows})
        :ok
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

      assert_receive {:completed, "success"}
      assert_receive {:steps, rows}

      assert [
               %{
                 workflow_job_id: 4242,
                 account_id: 777,
                 number: 1,
                 name: "Set up job",
                 status: "completed",
                 conclusion: "success",
                 started_at: %DateTime{} = started_at,
                 completed_at: %DateTime{} = completed_at
               }
             ] = rows

      assert DateTime.to_iso8601(started_at) =~ "2026-05-28T10:00:00"
      assert DateTime.to_iso8601(completed_at) =~ "2026-05-28T10:00:05"
    end

    test "skips the steps write entirely when the payload carries no steps" do
      test_pid = self()
      stub(Claims, :complete, fn _ -> :ok end)
      stub(Jobs, :complete, fn _id, _conclusion -> {:ok, %{account_id: 1}} end)

      stub(JobSteps, :record, fn rows ->
        send(test_pid, {:steps, rows})
        :ok
      end)

      assert {:ok, :completed} = Dispatch.handle_webhook(completed_payload(steps: []), 1)

      assert_receive {:steps, []}
    end
  end

  describe "handle_webhook/2 in_progress" do
    setup do
      account = enabled_account()
      stub(Accounts, :get_account_by_handle, fn _ -> account end)
      %{account: account}
    end

    test "records the runner→job binding and reports matched", %{account: account} do
      test_pid = self()
      account_id = account.id

      stub(Claims, :record_execution, fn "runner-a", 4300, ^account_id ->
        send(test_pid, {:claim_exec, "runner-a", 4300})
        :matched
      end)

      stub(RunnerSessions, :record_execution, fn "runner-a", 4300, ^account_id ->
        send(test_pid, {:session_exec, "runner-a", 4300})
        :matched
      end)

      assert {:ok, :matched} =
               Dispatch.handle_webhook(in_progress_payload(id: 4300, runner_name: "runner-a"), 1)

      assert_receive {:claim_exec, "runner-a", 4300}
      assert_receive {:session_exec, "runner-a", 4300}
    end

    test "surfaces a claim↔execution mismatch when GitHub ran a different job" do
      stub(Claims, :record_execution, fn "runner-b", 4400, _acct -> :mismatch end)
      stub(RunnerSessions, :record_execution, fn "runner-b", 4400, _acct -> :mismatch end)

      assert {:ok, :mismatch} =
               Dispatch.handle_webhook(in_progress_payload(id: 4400, runner_name: "runner-b"), 1)
    end

    test "a mismatch on either store wins over a matched on the other" do
      stub(Claims, :record_execution, fn _runner, _job, _acct -> :unknown_runner end)
      stub(RunnerSessions, :record_execution, fn _runner, _job, _acct -> :mismatch end)

      assert {:ok, :mismatch} =
               Dispatch.handle_webhook(in_progress_payload(id: 4500, runner_name: "runner-c"), 1)
    end

    test "ignores when neither store knows the runner" do
      stub(Claims, :record_execution, fn _runner, _job, _acct -> :unknown_runner end)
      stub(RunnerSessions, :record_execution, fn _runner, _job, _acct -> :unknown_runner end)

      assert {:ignored, :unknown_runner} =
               Dispatch.handle_webhook(in_progress_payload(id: 4600, runner_name: "runner-d"), 1)
    end

    test "ignores an in_progress payload with no runner_name" do
      assert :ignored = Dispatch.handle_webhook(in_progress_payload(id: 4700), 1)
    end

    test "ignores, touching no runner state, when the delivery resolves to no account" do
      # A runner_name is only ours to act on within the account that
      # minted it. With no account resolved from the installation we
      # must not match the name against anyone's runners.
      stub(Accounts, :get_account_by_handle, fn _ -> nil end)
      reject(&Claims.record_execution/3)
      reject(&RunnerSessions.record_execution/3)

      assert :ignored =
               Dispatch.handle_webhook(in_progress_payload(id: 4750, runner_name: "runner-x"), 1)
    end
  end

  describe "handle_webhook/2 completed — attribution backstop" do
    setup do
      account = enabled_account()
      stub(Accounts, :get_account_by_handle, fn _ -> account end)
      %{account: account}
    end

    test "binds the runner→job on the durable session before completing", %{account: account} do
      test_pid = self()
      account_id = account.id

      stub(RunnerSessions, :record_execution, fn "runner-late", 4800, ^account_id ->
        send(test_pid, {:session_exec, "runner-late", 4800})
        :matched
      end)

      stub(Claims, :complete_by_runner_name, fn "runner-late", ^account_id -> 1 end)
      stub(Jobs, :complete, fn _id, _conclusion -> {:ok, %{account_id: account_id}} end)
      stub(JobSteps, :record, fn _ -> :ok end)

      assert {:ok, :completed} =
               Dispatch.handle_webhook(
                 completed_payload(id: 4800, runner_name: "runner-late", steps: []),
                 1
               )

      assert_receive {:session_exec, "runner-late", 4800}
    end

    test "releases the executor's claim, scoped to the webhook's account", %{account: account} do
      test_pid = self()
      account_id = account.id

      stub(RunnerSessions, :record_execution, fn _r, _j, _a -> :matched end)

      stub(Claims, :complete_by_runner_name, fn runner, acct ->
        send(test_pid, {:released, runner, acct})
        1
      end)

      stub(Jobs, :complete, fn _id, _conclusion -> {:ok, %{account_id: account_id}} end)
      stub(JobSteps, :record, fn _ -> :ok end)

      assert {:ok, :completed} =
               Dispatch.handle_webhook(
                 completed_payload(id: 4850, runner_name: "runner-exec", steps: []),
                 1
               )

      assert_receive {:released, "runner-exec", ^account_id}
    end

    test "skips backstop attribution when the completed payload has no runner_name (cancelled-while-queued)" do
      stub(Claims, :complete, fn _ -> :ok end)
      stub(Jobs, :complete, fn _id, _conclusion -> {:ok, %{account_id: 1}} end)
      stub(JobSteps, :record, fn _ -> :ok end)

      reject(&RunnerSessions.record_execution/3)

      assert {:ok, :completed} = Dispatch.handle_webhook(completed_payload(id: 4900, steps: []), 1)
    end
  end

  describe "resolve_dispatch_target/2 — profile path" do
    setup do
      catalog_account = AccountsFixtures.organization_fixture(preload: [:account]).account

      catalog = [
        %{vcpus: 4, memory_gb: 16, key: "4vcpu-16gb", default?: true, pool_dispatch_label: ""},
        %{vcpus: 8, memory_gb: 32, key: "8vcpu-32gb", default?: false, pool_dispatch_label: ""}
      ]

      stub(Catalog, :shapes, fn
        :linux -> catalog
        :macos -> []
      end)

      stub(Catalog, :default_shape, fn
        :linux -> Enum.find(catalog, & &1.default?)
        :macos -> nil
      end)

      stub(Catalog, :xcode_versions, fn -> [] end)
      stub(Catalog, :default_xcode_version, fn -> nil end)

      {:ok, profile} =
        Profiles.create(catalog_account, %{
          "name" => "default",
          "vcpus" => 4,
          "memory_gb" => 16
        })

      %{account: catalog_account, profile: profile}
    end

    test "resolves through the profile to the shape pool name", %{account: account} do
      assert {:ok,
              %{
                pool_name: "tuist-runner-pool-linux-4vcpu-16gb",
                requested_dispatch_label: "tuist-default",
                platform: :linux,
                vcpus: 4,
                memory_gb: 16
              }} =
               Dispatch.resolve_dispatch_target(account, ["self-hosted", "tuist-default"])
    end

    test "falls back to legacy pool match for non-Linux labels (macOS)", %{account: account} do
      stub(Client, :list_runner_pools, fn _ns ->
        {:ok,
         [
           %{
             "metadata" => %{"name" => "macos-pool"},
             "spec" => %{
               "dispatchLabel" => "tuist-macos",
               "runnerLabels" => ["self-hosted", "macOS", "ARM64"]
             }
           }
         ]}
      end)

      assert {:ok,
              %{
                pool_name: "macos-pool",
                requested_dispatch_label: "tuist-macos"
              }} = Dispatch.resolve_dispatch_target(account, ["self-hosted", "tuist-macos"])
    end

    test "returns :no_matching_profile when neither path matches", %{account: account} do
      stub(Client, :list_runner_pools, fn _ns -> {:ok, []} end)

      # Legacy path returns :no_pools when there are no pools at all,
      # which trumps the profile-side miss.
      assert {:error, :no_pools} =
               Dispatch.resolve_dispatch_target(account, ["self-hosted", "tuist-unknown"])
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
             "os" => "linux",
             "podCPUMilli" => 7500,
             "podMemoryMB" => 18_000,
             "runnerLabels" => ["self-hosted", "Linux", "X64"]
           }
         }}
      end)

      assert {:ok,
              %{
                name: "linux-pool",
                dispatch_label: "tuist-linux-ubuntu-22-04",
                runner_labels: ["self-hosted", "Linux", "X64"],
                platform: :linux,
                vcpus: 8,
                memory_gb: 18
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
