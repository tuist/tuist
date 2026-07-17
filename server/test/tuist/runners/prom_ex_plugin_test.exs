defmodule Tuist.Runners.PromExPluginTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Kubernetes.Client, as: K8sClient
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

  defp stub_pool_list(fleets) when is_list(fleets) do
    items =
      Enum.map(fleets, fn name ->
        %{
          "metadata" => %{"name" => name},
          "spec" => %{"replicas" => 0, "dispatchLabel" => name},
          "status" => %{"observedReplicas" => 0}
        }
      end)

    Mimic.stub(K8sClient, :list_runner_pools, fn _ns -> {:ok, items} end)
  end

  describe "execute_queue_length_telemetry_event/0" do
    test "emits per-fleet queue length gauges", %{handler_id: handler_id} do
      attach_collector(handler_id, Telemetry.event_name_queue_length())
      stub_pool_list(["fleet-poll"])

      account = account_fixture()

      :ok =
        Jobs.enqueue(%{
          workflow_job_id: 999_001,
          account_id: account.id,
          fleet_name: "fleet-poll",
          repository: "acme/cli",
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

    test "drains to zero for fleets with no remaining queued rows", %{handler_id: handler_id} do
      attach_collector(handler_id, Telemetry.event_name_queue_length())

      # Fleet is declared in the cluster but has no queued rows in
      # ClickHouse. Without the drain-to-zero path, `last_value`
      # would keep whatever the last non-zero sample was; this
      # asserts we emit an explicit `0` instead.
      stub_pool_list(["fleet-empty"])

      PromExPlugin.execute_queue_length_telemetry_event()

      assert_receive {:telemetry_event, [:tuist, :runners, :queue, :length], %{count: 0}, %{fleet: "fleet-empty"}},
                     500
    end

    test "reports the age of the oldest queued job", %{handler_id: handler_id} do
      attach_collector(handler_id, Telemetry.event_name_queue_length())
      stub_pool_list(["fleet-age"])

      account = account_fixture()

      # Two queued jobs on one fleet: the gauge tracks the oldest.
      for {id, enqueued_at} <- [
            {999_010, ~U[2026-07-16 22:39:43.000000Z]},
            {999_011, ~U[2026-07-17 02:00:00.000000Z]}
          ] do
        :ok =
          Jobs.enqueue(%{
            workflow_job_id: id,
            account_id: account.id,
            fleet_name: "fleet-age",
            repository: "acme/cli",
            workflow_run_id: 9010,
            run_attempt: 1,
            job_name: "build",
            head_branch: "main",
            head_sha: "deadbeef",
            enqueued_at: enqueued_at
          })
      end

      PromExPlugin.execute_queue_length_telemetry_event()

      assert_receive {:telemetry_event, [:tuist, :runners, :queue, :length],
                      %{count: 2, oldest_age_seconds: oldest_age_seconds}, %{fleet: "fleet-age"}},
                     500

      expected = DateTime.diff(DateTime.utc_now(), ~U[2026-07-16 22:39:43.000000Z], :second)
      assert_in_delta oldest_age_seconds, expected, 60
    end

    test "reports zero age for a fleet with an empty queue", %{handler_id: handler_id} do
      attach_collector(handler_id, Telemetry.event_name_queue_length())
      stub_pool_list(["fleet-empty-age"])

      PromExPlugin.execute_queue_length_telemetry_event()

      assert_receive {:telemetry_event, [:tuist, :runners, :queue, :length], %{oldest_age_seconds: 0},
                      %{fleet: "fleet-empty-age"}},
                     500
    end
  end

  describe "execute_claims_telemetry_event/0" do
    test "emits per-fleet per-lifecycle gauges", %{handler_id: handler_id} do
      attach_collector(handler_id, Telemetry.event_name_claims_count())
      stub_pool_list(["fleet-claims"])

      account = account_fixture()

      {:ok, _} =
        Claims.attempt(123_456, account.id, "fleet-claims", "pod-x", %{
          platform: :linux,
          vcpus: 1,
          memory_gb: 1
        })

      PromExPlugin.execute_claims_telemetry_event()

      assert_receive {:telemetry_event, [:tuist, :runners, :claims, :count], %{count: 1},
                      %{fleet: "fleet-claims", lifecycle_state: "claimed"}},
                     500
    end

    test "drains to zero for both lifecycle states when no claims remain", %{handler_id: handler_id} do
      attach_collector(handler_id, Telemetry.event_name_claims_count())
      stub_pool_list(["fleet-drained"])

      PromExPlugin.execute_claims_telemetry_event()

      assert_receive {:telemetry_event, [:tuist, :runners, :claims, :count], %{count: 0},
                      %{fleet: "fleet-drained", lifecycle_state: "claimed"}},
                     500

      assert_receive {:telemetry_event, [:tuist, :runners, :claims, :count], %{count: 0},
                      %{fleet: "fleet-drained", lifecycle_state: "running"}},
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
             "metadata" => %{"name" => "pool-emit"},
             "spec" => %{"replicas" => 3, "dispatchLabel" => "tuist-runner-pool-emit"},
             "status" => %{"observedReplicas" => 2}
           }
         ]}
      end)

      PromExPlugin.execute_pool_replicas_telemetry_event()

      assert_receive {:telemetry_event, [:tuist, :runners, :pool, :replicas], %{desired: 3, observed: 2},
                      %{fleet: "pool-emit"}},
                     500
    end

    test "max gauge reports the autoscaling ceiling when set", %{handler_id: handler_id} do
      attach_collector(handler_id, Telemetry.event_name_pool_replicas())

      Mimic.stub(K8sClient, :list_runner_pools, fn _ns ->
        {:ok,
         [
           %{
             "metadata" => %{"name" => "pool-autoscaled"},
             "spec" => %{"replicas" => 10, "autoscaling" => %{"enabled" => true, "maxReplicas" => 40}},
             "status" => %{"observedReplicas" => 10}
           }
         ]}
      end)

      PromExPlugin.execute_pool_replicas_telemetry_event()

      assert_receive {:telemetry_event, [:tuist, :runners, :pool, :replicas], %{desired: 10, observed: 10, max: 40},
                      %{fleet: "pool-autoscaled"}},
                     500
    end

    test "drains a pool to zero on the tick after it disappears from the cluster",
         %{handler_id: handler_id} do
      attach_collector(handler_id, Telemetry.event_name_pool_replicas())

      # Tick 1 — pool is alive.
      Mimic.stub(K8sClient, :list_runner_pools, fn _ns ->
        {:ok,
         [
           %{
             "metadata" => %{"name" => "pool-deleting"},
             "spec" => %{"replicas" => 5},
             "status" => %{"observedReplicas" => 5}
           }
         ]}
      end)

      PromExPlugin.execute_pool_replicas_telemetry_event()

      assert_receive {:telemetry_event, [:tuist, :runners, :pool, :replicas], %{desired: 5, observed: 5},
                      %{fleet: "pool-deleting"}},
                     500

      # Tick 2 — pool has been deleted. We expect an explicit `0`
      # so `last_value` stops reporting the stale `5`.
      Mimic.stub(K8sClient, :list_runner_pools, fn _ns -> {:ok, []} end)

      PromExPlugin.execute_pool_replicas_telemetry_event()

      assert_receive {:telemetry_event, [:tuist, :runners, :pool, :replicas], %{desired: 0, observed: 0},
                      %{fleet: "pool-deleting"}},
                     500
    end

    test "returns :ok when the K8s client is unavailable" do
      Mimic.stub(K8sClient, :list_runner_pools, fn _ns -> {:error, :not_in_cluster} end)

      assert :ok = PromExPlugin.execute_pool_replicas_telemetry_event()
    end
  end
end
