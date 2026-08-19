defmodule Tuist.Kura.PromExPluginTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.IngestRepo
  alias Tuist.KeyValueStore
  alias Tuist.Kubernetes.Client
  alias Tuist.Kura.Demand
  alias Tuist.Kura.PromExPlugin
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Kura.UsageEvent
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :set_mimic_from_context

  @region "us-east"
  # Roughly what one of the region's real boxes reports allocatable.
  @node_allocatable_bytes 847_551_469_804

  setup do
    stub(Environment, :env, fn -> :prod end)
    stub(Environment, :dev?, fn -> false end)
    stub(Environment, :test?, fn -> false end)
    stub(Environment, :tuist_hosted?, fn -> true end)
    stub(Environment, :kura_available_region_ids, fn -> [@region] end)
    stub_region_nodes([])
    :ok
  end

  defp account do
    user = AccountsFixtures.user_fixture()
    Accounts.get_account_from_user(user)
  end

  defp instance(account) do
    Repo.insert!(%Server{
      account_id: account.id,
      region: @region,
      status: :active,
      provisioner_node_ref: "kura-#{account.id}-us-east"
    })
  end

  defp insert_usage(account_id, operation, request_count) do
    window_start = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    IngestRepo.insert_all(UsageEvent, [
      %{
        event_id: "evt-#{System.unique_integer([:positive])}",
        account_id: account_id,
        project_id: 0,
        node_id: "kura-test",
        region: @region,
        traffic_plane: "public",
        direction: "egress",
        operation: operation,
        protocol: "http",
        artifact_kind: "xcframework",
        bytes: 1,
        request_count: request_count,
        window_start: window_start,
        window_seconds: 3_600,
        inserted_at: window_start
      }
    ])
  end

  describe "execute_occupancy_telemetry_event/0" do
    test "reports the region's forecast, installed capacity, and instance count" do
      stub_region_nodes([{@region, List.duplicate(@node_allocatable_bytes, 2)}])
      instance(account())

      ref = :telemetry_test.attach_event_handlers(self(), [[:tuist, :kura, :capacity, :occupancy]])

      PromExPlugin.execute_occupancy_telemetry_event()

      assert_received {[:tuist, :kura, :capacity, :occupancy], ^ref, measurements, %{region: @region}}
      assert measurements.instances == 1
      assert measurements.forecast_gib == 24 * 2
      assert measurements.installed_gib == trunc(2 * @node_allocatable_bytes * 0.85 / (1024 * 1024 * 1024))
    end

    test "reports zero installed capacity rather than dropping the series when unconfigured" do
      instance(account())

      ref = :telemetry_test.attach_event_handlers(self(), [[:tuist, :kura, :capacity, :occupancy]])

      PromExPlugin.execute_occupancy_telemetry_event()

      assert_received {[:tuist, :kura, :capacity, :occupancy], ^ref, %{installed_gib: 0}, _metadata}
    end
  end

  describe "execute_hit_rate_recovery_telemetry_event/0" do
    test "separates account-regions that recently returned from archive" do
      returned = account()
      steady = account()

      {:ok, _} = Demand.upsert(returned.id, @region, DateTime.utc_now())

      returned.id
      |> Demand.get(@region)
      |> Ecto.Changeset.change(%{last_returned_at: DateTime.truncate(DateTime.utc_now(), :second)})
      |> Repo.update!()

      {:ok, _} = Demand.upsert(steady.id, @region, DateTime.utc_now())

      # A returned instance is refilling, so more of its traffic is uploads.
      insert_usage(returned.id, "download", 1)
      insert_usage(returned.id, "upload", 3)
      insert_usage(steady.id, "download", 9)
      insert_usage(steady.id, "upload", 1)

      ref = :telemetry_test.attach_event_handlers(self(), [[:tuist, :kura, :lifecycle, :hit_rate_recovery]])

      PromExPlugin.execute_hit_rate_recovery_telemetry_event()

      assert_received {[:tuist, :kura, :lifecycle, :hit_rate_recovery], ^ref, measurements, %{region: @region}}
      assert_in_delta measurements.returned_hit_rate, 0.25, 0.001
      assert_in_delta measurements.steady_hit_rate, 0.9, 0.001
    end

    test "reports zero rather than crashing with no usage in the window" do
      ref = :telemetry_test.attach_event_handlers(self(), [[:tuist, :kura, :lifecycle, :hit_rate_recovery]])

      PromExPlugin.execute_hit_rate_recovery_telemetry_event()

      assert_received {[:tuist, :kura, :lifecycle, :hit_rate_recovery], ^ref,
                       %{returned_hit_rate: +0.0, steady_hit_rate: +0.0}, _metadata}
    end
  end

  # `installed_gib/1` sums the allocatable ephemeral storage of a region's
  # Ready nodes, so sizing a region in a test means answering the node list.
  defp stub_region_nodes(nodes_by_region) do
    stub(KeyValueStore, :get_or_update, fn _key, _opts, func -> func.() end)

    stub(Client, :list_nodes, fn selector ->
      allocatable =
        Enum.find_value(nodes_by_region, [], fn {region_id, allocatable} ->
          {:ok, region} = Regions.fetch(region_id)
          if selector == Regions.node_label_selector(region), do: allocatable
        end)

      {:ok, %{"items" => Enum.map(allocatable, &ready_node/1)}}
    end)
  end

  defp ready_node(allocatable_bytes) do
    %{
      "status" => %{
        "conditions" => [%{"type" => "Ready", "status" => "True"}],
        "allocatable" => %{"ephemeral-storage" => Integer.to_string(allocatable_bytes)}
      }
    }
  end
end
