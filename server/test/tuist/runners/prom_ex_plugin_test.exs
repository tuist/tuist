defmodule Tuist.Runners.PromExPluginTest do
  use TuistTestSupport.Cases.DataCase, async: false

  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts.Account
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Repo
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.PromExPlugin
  alias Tuist.Runners.Telemetry

  setup do
    handler_id = make_ref()

    on_exit(fn -> :telemetry.detach(handler_id) end)

    {:ok, handler_id: handler_id}
  end

  defp attach_collector(handler_id, event_name) do
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        event_name,
        fn name, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, name, measurements, metadata})
        end,
        nil
      )
  end

  defp enabled_account_fixture(cap \\ 10) do
    account = account_fixture()
    {1, _} = Repo.update_all(from(a in Account, where: a.id == ^account.id), set: [runner_max_concurrent: cap])
    Repo.reload!(account)
  end

  describe "execute_queue_length_telemetry_event/0" do
    test "emits per-fleet queue length gauges", %{handler_id: handler_id} do
      attach_collector(handler_id, Telemetry.event_name_queue_length())

      account = enabled_account_fixture()

      :ok =
        Jobs.enqueue(%{
          workflow_job_id: 999_001,
          account_id: account.id,
          fleet_name: "fleet-poll",
          repo: "acme/cli",
          workflow_run_id: 9001,
          run_attempt: 1,
          job_name: "build",
          head_branch: "main",
          head_sha: "deadbeef"
        })

      PromExPlugin.execute_queue_length_telemetry_event()

      assert_receive {:telemetry_event, [:tuist, :runners, :queue, :length], %{count: 1}, %{fleet: "fleet-poll"}},
                     500
    end
  end

  describe "execute_claims_telemetry_event/0" do
    test "emits per-fleet per-lifecycle gauges", %{handler_id: handler_id} do
      attach_collector(handler_id, Telemetry.event_name_claims_count())

      account = enabled_account_fixture()
      {:ok, _} = Claims.attempt(123_456, account.id, "fleet-claims", "pod-x")

      PromExPlugin.execute_claims_telemetry_event()

      assert_receive {:telemetry_event, [:tuist, :runners, :claims, :count], %{count: 1},
                      %{fleet: "fleet-claims", lifecycle_state: "claimed"}},
                     500
    end
  end

  describe "execute_pool_replicas_telemetry_event/0" do
    test "emits desired + observed gauges per pool", %{handler_id: handler_id} do
      attach_collector(handler_id, Telemetry.event_name_pool_replicas())

      Mimic.stub(K8sClient, :list_runner_pools, fn _ns ->
        {:ok,
         [
           %{
             "metadata" => %{"name" => "default"},
             "spec" => %{"replicas" => 3, "dispatchLabel" => "tuist-runner-default"},
             "status" => %{"observedReplicas" => 2}
           }
         ]}
      end)

      PromExPlugin.execute_pool_replicas_telemetry_event()

      assert_receive {:telemetry_event, [:tuist, :runners, :pool, :replicas], %{desired: 3, observed: 2},
                      %{fleet: "default", dispatch_label: "tuist-runner-default"}},
                     500
    end

    test "tolerates a missing K8s client", %{handler_id: handler_id} do
      attach_collector(handler_id, Telemetry.event_name_pool_replicas())

      Mimic.stub(K8sClient, :list_runner_pools, fn _ns -> {:error, :not_in_cluster} end)

      assert :ok = PromExPlugin.execute_pool_replicas_telemetry_event()

      refute_receive {:telemetry_event, [:tuist, :runners, :pool, :replicas], _, _}, 200
    end
  end

  describe "execute_accounts_enabled_telemetry_event/0" do
    test "emits the count of accounts with runner_max_concurrent > 0", %{handler_id: handler_id} do
      attach_collector(handler_id, Telemetry.event_name_accounts_enabled())

      _ = enabled_account_fixture()
      _ = enabled_account_fixture()
      _ = account_fixture()

      PromExPlugin.execute_accounts_enabled_telemetry_event()

      assert_receive {:telemetry_event, [:tuist, :runners, :accounts, :enabled], %{count: count}, _}, 500
      assert count >= 2
    end
  end
end
