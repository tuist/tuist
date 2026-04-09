defmodule TuistCommon.Repo.PromExPluginTest do
  use ExUnit.Case, async: false
  use Mimic

  defmodule TestRepoPromExPlugin do
    use TuistCommon.Repo.PromExPlugin,
      name: :test_repo,
      metrics_prefix: [:test, :repo, :pool],
      pool_metrics_event_name: [:test, :repo, :pool, :metrics],
      repos: [
        {:test_repo, %{repo: "postgres", database: "postgres"}}
      ]
  end

  setup do
    handler_id = "repo-prom-ex-plugin-test-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:test, :repo, :pool, :metrics],
        fn event_name, measurements, metadata, pid ->
          send(pid, {:telemetry_event, event_name, measurements, metadata})
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  describe "execute_repo_pool_metrics_event/0" do
    test "emits queue pressure measurements for contended pools" do
      stub(TuistCommon.Repo.PoolMetrics, :running?, fn :test_repo -> true end)

      stub(TuistCommon.Repo.PoolMetrics, :connection_pool_metrics, fn :test_repo ->
        %{
          checkout_queue_length: 3,
          ready_conn_count: 0,
          pool_size: 10
        }
      end)

      TestRepoPromExPlugin.execute_repo_pool_metrics_event()

      assert_receive {:telemetry_event, [:test, :repo, :pool, :metrics], measurements,
                      %{repo: "postgres", database: "postgres"}}

      assert measurements.checkout_queue_length == 3
      assert measurements.ready_conn_count == 0
      assert measurements.checkout_queue_observed == 3
      assert measurements.checkout_queue_busy_count == 1
      assert measurements.checkout_queue_starved_count == 1
    end

    test "emits zeroed queue pressure counters when the pool is idle" do
      stub(TuistCommon.Repo.PoolMetrics, :running?, fn :test_repo -> true end)

      stub(TuistCommon.Repo.PoolMetrics, :connection_pool_metrics, fn :test_repo ->
        %{
          checkout_queue_length: 0,
          ready_conn_count: 4,
          pool_size: 10
        }
      end)

      TestRepoPromExPlugin.execute_repo_pool_metrics_event()

      assert_receive {:telemetry_event, [:test, :repo, :pool, :metrics], measurements,
                      %{repo: "postgres", database: "postgres"}}

      assert measurements.checkout_queue_observed == 0
      assert measurements.checkout_queue_busy_count == 0
      assert measurements.checkout_queue_starved_count == 0
    end
  end
end
