defmodule Tuist.Kura.PromExPluginTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.IngestRepo
  alias Tuist.KeyValueStore
  alias Tuist.Kubernetes.Client
  alias Tuist.Kura
  alias Tuist.Kura.Capacity
  alias Tuist.Kura.Demand
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.PromExPlugin
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Kura.Telemetry
  alias Tuist.Kura.UsageEvent
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :set_mimic_from_context

  @region "us-east"
  # Roughly what one of the region's real boxes reports allocatable.
  @node_allocatable_bytes 847_551_469_804
  @gib 1024 * 1024 * 1024

  setup do
    stub(Environment, :env, fn -> :prod end)
    stub(Environment, :dev?, fn -> false end)
    stub(Environment, :test?, fn -> false end)
    stub(Environment, :tuist_hosted?, fn -> true end)
    stub(Environment, :kura_available_region_ids, fn -> [@region] end)
    stub_region_nodes([])
    :ok
  end

  describe "event metrics" do
    test "every telemetry event the lifecycle emits is scraped" do
      # A counter nothing scrapes is a decision nobody can see. The unmet
      # placement preference is the one that matters most here: it is the
      # procurement signal, and it is emitted from a path that produces no
      # other trace of itself.
      scraped =
        []
        |> PromExPlugin.event_metrics()
        |> Enum.flat_map(& &1.metrics)
        |> MapSet.new(& &1.event_name)

      for event <- [
            Telemetry.event_name_provisioned(),
            Telemetry.event_name_ready(),
            Telemetry.event_name_drain_pending(),
            Telemetry.event_name_archive_cancelled(),
            Telemetry.event_name_archived(),
            Telemetry.event_name_resolution_refused(),
            Telemetry.event_name_seed_declined(),
            Telemetry.event_name_placement_preference_unmet(),
            Telemetry.event_name_placement_capacity_spill(),
            Telemetry.event_name_claim_apply_refused(),
            Telemetry.event_name_provision_refused()
          ] do
        assert MapSet.member?(scraped, event), "#{inspect(event)} is emitted but never scraped"
      end
    end
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

  # The stall clock is the open deployment's age, so a stalled instance is one
  # whose attempt started before the threshold and never closed.
  defp open_deployment(server, age_seconds: age_seconds) do
    Repo.insert!(%Deployment{
      cluster_id: "test-cluster",
      image_tag: "0.5.2",
      kura_server_id: server.id,
      status: :running,
      inserted_at: DateTime.add(DateTime.utc_now(), -age_seconds, :second)
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
    test "reports the region's reservation, allocatable disk, and instance count" do
      stub_region_nodes([{@region, List.duplicate(@node_allocatable_bytes, 2)}],
        pods: [reserved_pod(50), reserved_pod(50)]
      )

      instance(account())

      ref = :telemetry_test.attach_event_handlers(self(), [[:tuist, :kura, :capacity, :occupancy]])

      PromExPlugin.execute_occupancy_telemetry_event()

      assert_received {[:tuist, :kura, :capacity, :occupancy], ^ref, measurements, %{region: @region}}
      assert measurements.instances == 1
      assert measurements.reserved_gib == 100
      assert measurements.allocatable_gib == trunc(2 * @node_allocatable_bytes / (1024 * 1024 * 1024))
    end

    test "reports zero rather than dropping the series when the cluster cannot be read" do
      instance(account())

      ref = :telemetry_test.attach_event_handlers(self(), [[:tuist, :kura, :capacity, :occupancy]])

      PromExPlugin.execute_occupancy_telemetry_event()

      assert_received {[:tuist, :kura, :capacity, :occupancy], ^ref, %{allocatable_gib: 0, reserved_gib: 0}, _metadata}
    end
  end

  describe "execute_admission_headroom_telemetry_event/0" do
    setup do
      stub(Environment, :kura_capacity_admission_required?, fn -> true end)
      :ok
    end

    test "is scraped as a per-region gauge" do
      scraped =
        []
        |> PromExPlugin.polling_metrics()
        |> Enum.flat_map(& &1.metrics)
        |> Map.new(&{&1.name, &1.tags})

      assert Map.fetch!(scraped, [:tuist, :kura, :capacity, :admission_headroom, :gibibytes]) == [:region]
    end

    test "reports what admission can still place: the pressure line less the larger reservation" do
      stub_region_nodes([{@region, List.duplicate(@node_allocatable_bytes, 2)}],
        pods: [reserved_pod(50), reserved_pod(50)]
      )

      instance(account())
      pressure_line = trunc(trunc(2 * @node_allocatable_bytes / @gib) * 0.85)

      ref = :telemetry_test.attach_event_handlers(self(), [[:tuist, :kura, :capacity, :admission]])

      PromExPlugin.execute_admission_headroom_telemetry_event()

      assert_received {[:tuist, :kura, :capacity, :admission], ^ref, %{headroom_gib: headroom}, %{region: @region}}
      assert headroom == pressure_line - 100
    end

    test "reports the cached reading placement acts on rather than measuring again" do
      expect(Capacity, :admission_headroom_gib, fn %Regions{id: @region} -> 42 end)

      ref = :telemetry_test.attach_event_handlers(self(), [[:tuist, :kura, :capacity, :admission]])

      PromExPlugin.execute_admission_headroom_telemetry_event()

      assert_received {[:tuist, :kura, :capacity, :admission], ^ref, %{headroom_gib: 42}, %{region: @region}}
    end

    test "reports zero when the region cannot be read, because admission then refuses every instance" do
      instance(account())

      ref = :telemetry_test.attach_event_handlers(self(), [[:tuist, :kura, :capacity, :admission]])

      PromExPlugin.execute_admission_headroom_telemetry_event()

      assert_received {[:tuist, :kura, :capacity, :admission], ^ref, %{headroom_gib: 0}, %{region: @region}}
    end

    test "reports nothing where admission is not enforced" do
      stub(Environment, :kura_capacity_admission_required?, fn -> false end)

      ref = :telemetry_test.attach_event_handlers(self(), [[:tuist, :kura, :capacity, :admission]])

      PromExPlugin.execute_admission_headroom_telemetry_event()

      refute_received {[:tuist, :kura, :capacity, :admission], ^ref, _measurements, _metadata}
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

  describe "execute_new_instance_readiness_telemetry_event/0" do
    defp spin_up(server, seconds_ago: seconds_ago, took: took) do
      finished_at = DateTime.add(DateTime.utc_now(), -seconds_ago, :second)

      Repo.insert!(%Deployment{
        cluster_id: "test-cluster",
        image_tag: "0.5.2",
        kura_server_id: server.id,
        status: :succeeded,
        inserted_at: DateTime.add(finished_at, -took, :second),
        finished_at: DateTime.truncate(finished_at, :second)
      })
    end

    # An account-region the lifecycle tracks, so the instance is one resolution
    # hands out rather than a runner cache node.
    defp tracked_instance do
      account = account()
      {:ok, _lifecycle} = Demand.upsert(account.id, @region, DateTime.utc_now())
      {account, instance(account)}
    end

    test "reports how long the window's new instances took to serve" do
      for took <- [10, 20, 30, 300] do
        {_account, server} = tracked_instance()
        spin_up(server, seconds_ago: 600, took: took)
      end

      ref = :telemetry_test.attach_event_handlers(self(), [[:tuist, :kura, :lifecycle, :new_instance_readiness]])

      PromExPlugin.execute_new_instance_readiness_telemetry_event()

      assert_received {[:tuist, :kura, :lifecycle, :new_instance_readiness], ^ref, %{count: 4, p90_seconds: p90_seconds},
                       %{}}

      assert p90_seconds > 30 and p90_seconds <= 300
    end

    test "leaves out a rollout of an instance that was already serving" do
      {_account, server} = tracked_instance()
      spin_up(server, seconds_ago: 1200, took: 20)
      spin_up(server, seconds_ago: 600, took: 300)

      ref = :telemetry_test.attach_event_handlers(self(), [[:tuist, :kura, :lifecycle, :new_instance_readiness]])

      PromExPlugin.execute_new_instance_readiness_telemetry_event()

      assert_received {[:tuist, :kura, :lifecycle, :new_instance_readiness], ^ref, %{count: 1, p90_seconds: p90_seconds},
                       %{}}

      assert_in_delta p90_seconds, 20, 1
    end

    test "counts the deployment that returned an instance from archive" do
      {account, server} = tracked_instance()
      # The provision that first brought this instance up is outside the window.
      spin_up(server, seconds_ago: 2 * 24 * 3600, took: 20)
      returned_at = DateTime.utc_now() |> DateTime.add(-900, :second) |> DateTime.truncate(:second)

      account.id
      |> Demand.get(@region)
      |> Ecto.Changeset.change(%{last_returned_at: returned_at})
      |> Repo.update!()

      spin_up(server, seconds_ago: 600, took: 300)

      ref = :telemetry_test.attach_event_handlers(self(), [[:tuist, :kura, :lifecycle, :new_instance_readiness]])

      PromExPlugin.execute_new_instance_readiness_telemetry_event()

      assert_received {[:tuist, :kura, :lifecycle, :new_instance_readiness], ^ref, %{count: 1, p90_seconds: p90_seconds},
                       %{}}

      assert_in_delta p90_seconds, 300, 1
    end

    test "counts the deployment that superseded a provision still coming up" do
      # A runtime image bump landing mid-provision supersedes the open
      # deployment and schedules a second one, and that second deployment is
      # what actually brings the instance into service. Disqualifying it on the
      # superseded row's existence would drop the instance from the
      # measurement, and drop it one-directionally: only ever instances that
      # were coming up during a rollout, which is itself a reason a cold start
      # is slow.
      {_account, server} = tracked_instance()

      Repo.insert!(%Deployment{
        cluster_id: "test-cluster",
        image_tag: "0.5.1",
        kura_server_id: server.id,
        status: :superseded,
        inserted_at: DateTime.add(DateTime.utc_now(), -1200, :second),
        finished_at: DateTime.utc_now() |> DateTime.add(-1100, :second) |> DateTime.truncate(:second)
      })

      spin_up(server, seconds_ago: 600, took: 300)

      ref = :telemetry_test.attach_event_handlers(self(), [[:tuist, :kura, :lifecycle, :new_instance_readiness]])

      PromExPlugin.execute_new_instance_readiness_telemetry_event()

      assert_received {[:tuist, :kura, :lifecycle, :new_instance_readiness], ^ref, %{count: 1, p90_seconds: p90_seconds},
                       %{}}

      assert_in_delta p90_seconds, 300, 1
    end

    test "reports a zero count with no new instance in the window, so the alert's sample gate closes" do
      # A `last_value` is an ETS row the exporter reads back with no TTL and no
      # delete path, so a series that stops being emitted goes stale rather
      # than absent. Emitting nothing would leave the alert evaluating the
      # previous day's percentile against the previous day's sample count,
      # staying green through exactly the wedged-provisioning day it should
      # notice. The count going to zero is what takes the rule to No Data.
      {_account, server} = tracked_instance()
      spin_up(server, seconds_ago: 3 * 24 * 3600, took: 20)

      ref = :telemetry_test.attach_event_handlers(self(), [[:tuist, :kura, :lifecycle, :new_instance_readiness]])

      PromExPlugin.execute_new_instance_readiness_telemetry_event()

      assert_received {[:tuist, :kura, :lifecycle, :new_instance_readiness], ^ref, measurements, %{}}
      assert measurements == %{count: 0}
    end
  end

  describe "execute_unroutable_instances_telemetry_event/0" do
    test "counts instances that exist but cannot be resolved" do
      instance(account())

      account()
      |> instance()
      |> Ecto.Changeset.change(status: :failed, url: nil, current_image_tag: nil)
      |> Repo.update!()

      ref = :telemetry_test.attach_event_handlers(self(), [[:tuist, :kura, :lifecycle, :instance_routability]])

      PromExPlugin.execute_unroutable_instances_telemetry_event()

      assert_received {[:tuist, :kura, :lifecycle, :instance_routability], ^ref, %{unroutable: 1}, %{region: @region}}
    end

    test "reports zero for a healthy region rather than dropping the series" do
      instance(account())

      ref = :telemetry_test.attach_event_handlers(self(), [[:tuist, :kura, :lifecycle, :instance_routability]])

      PromExPlugin.execute_unroutable_instances_telemetry_event()

      assert_received {[:tuist, :kura, :lifecycle, :instance_routability], ^ref, %{unroutable: 0}, %{region: @region}}
    end

    test "counts an instance whose provisioning attempt has run past the stall threshold as stalled" do
      account()
      |> instance()
      |> Ecto.Changeset.change(status: :provisioning, url: nil, current_image_tag: nil)
      |> Repo.update!()
      |> open_deployment(age_seconds: Kura.provisioning_stall_seconds() + 60)

      ref = :telemetry_test.attach_event_handlers(self(), [[:tuist, :kura, :lifecycle, :instance_routability]])

      PromExPlugin.execute_unroutable_instances_telemetry_event()

      assert_received {[:tuist, :kura, :lifecycle, :instance_routability], ^ref, %{unroutable: 1, stalled: 1},
                       %{region: @region}}
    end

    test "does not count an instance that is merely starting as stalled" do
      account()
      |> instance()
      |> Ecto.Changeset.change(status: :provisioning, url: nil, current_image_tag: nil)
      |> Repo.update!()
      |> open_deployment(age_seconds: 30)

      ref = :telemetry_test.attach_event_handlers(self(), [[:tuist, :kura, :lifecycle, :instance_routability]])

      PromExPlugin.execute_unroutable_instances_telemetry_event()

      assert_received {[:tuist, :kura, :lifecycle, :instance_routability], ^ref, %{unroutable: 1, stalled: 0},
                       %{region: @region}}
    end

    test "stops counting an instance as stalled once its deployment closes" do
      account()
      |> instance()
      |> Ecto.Changeset.change(status: :provisioning, url: nil, current_image_tag: nil)
      |> Repo.update!()
      |> open_deployment(age_seconds: Kura.provisioning_stall_seconds() + 60)
      |> Ecto.Changeset.change(status: :succeeded)
      |> Repo.update!()

      ref = :telemetry_test.attach_event_handlers(self(), [[:tuist, :kura, :lifecycle, :instance_routability]])

      PromExPlugin.execute_unroutable_instances_telemetry_event()

      assert_received {[:tuist, :kura, :lifecycle, :instance_routability], ^ref, %{stalled: 0}, %{region: @region}}
    end
  end

  # Capacity reads the region's nodes and pods, so sizing a region in a test
  # means answering both lists.
  defp stub_region_nodes(nodes_by_region, opts \\ []) do
    stub(KeyValueStore, :get_or_update, fn _key, _opts, func -> func.() end)
    stub_region_pods(Keyword.get(opts, :pods, []))

    stub(Client, :list_nodes, fn selector ->
      allocatable =
        Enum.find_value(nodes_by_region, [], fn {region_id, allocatable} ->
          {:ok, region} = Regions.fetch(region_id)
          if selector == Regions.node_label_selector(region), do: allocatable
        end)

      {:ok, %{"items" => Enum.map(allocatable, &ready_node/1)}}
    end)
  end

  defp stub_region_pods(pods) do
    stub(Client, :list_pods, fn _namespace, _selector -> {:ok, pods} end)
  end

  defp reserved_pod(gib) do
    %{
      "status" => %{"phase" => "Running"},
      "spec" => %{
        "containers" => [%{"resources" => %{"requests" => %{"ephemeral-storage" => "#{gib}Gi"}}}]
      }
    }
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
