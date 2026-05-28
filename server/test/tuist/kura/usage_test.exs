defmodule Tuist.Kura.UsageTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.IngestRepo
  alias Tuist.Kura.Usage
  alias Tuist.Kura.UsageEvent
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  # ClickHouse INSERTs don't roll back with the Postgres sandbox. Each test
  # uses a unique account_id so it can't observe rows from another test, and
  # the on_exit callback wipes everything that test inserted. The Agent is
  # started under ExUnit's per-test supervisor so it outlives the test
  # process and is still alive when on_exit fires.
  setup do
    account_ids_pid = start_supervised!({Agent, fn -> MapSet.new() end})

    on_exit(fn ->
      ids =
        case Process.info(account_ids_pid) do
          nil -> []
          _ -> account_ids_pid |> Agent.get(& &1) |> MapSet.to_list()
        end

      if ids != [] do
        IngestRepo.query!(
          "DELETE FROM kura_usage_events WHERE account_id IN {ids:Array(Int64)}",
          %{ids: ids}
        )
      end
    end)

    {:ok, account_ids_pid: account_ids_pid}
  end

  defp insert_event(attrs, %{account_ids_pid: account_ids_pid}) do
    account_id = Map.fetch!(attrs, :account_id)
    Agent.update(account_ids_pid, &MapSet.put(&1, account_id))

    base = %{
      event_id: "evt-#{System.unique_integer([:positive])}",
      account_id: account_id,
      project_id: 0,
      node_id: "kura-test",
      region: "us-east-1",
      traffic_plane: "public",
      direction: "egress",
      operation: "download",
      protocol: "http",
      artifact_kind: "xcframework",
      bytes: 0,
      request_count: 0,
      window_start: ~N[2026-05-01 12:00:00],
      window_seconds: 3_600,
      inserted_at: ~N[2026-05-01 12:00:00]
    }

    IngestRepo.insert_all(UsageEvent, [Map.merge(base, attrs)])
  end

  defp window_span do
    {
      ~U[2026-05-01 00:00:00Z],
      ~U[2026-05-08 00:00:00Z]
    }
  end

  describe "create_events/1" do
    test "resolves tenant/namespace handles to account/project ids", ctx do
      account = AccountsFixtures.organization_fixture(name: "acme-#{System.unique_integer([:positive])}").account
      project = ProjectsFixtures.project_fixture(account: account, name: "ios")
      Agent.update(ctx.account_ids_pid, &MapSet.put(&1, account.id))

      {:ok, 1} =
        Usage.create_events([
          %{
            "event_id" => "wire-1",
            "tenant_id" => account.name,
            "namespace_id" => "ios",
            "node_id" => "kura-0",
            "region" => "us-east-1",
            "traffic_plane" => "public",
            "direction" => "egress",
            "operation" => "download",
            "protocol" => "http",
            "artifact_kind" => "xcframework",
            "bytes" => 100,
            "request_count" => 1,
            "window_start_unix_seconds" => 1_777_968_000,
            "window_seconds" => 60
          }
        ])

      import Ecto.Query

      assert [%UsageEvent{account_id: a_id, project_id: p_id, bytes: 100}] =
               Tuist.ClickHouseRepo.all(from(e in UsageEvent, where: e.account_id == ^account.id))

      assert a_id == account.id
      assert p_id == project.id
    end

    test "falls back to account_id alone when only the account handle resolves", ctx do
      handle = "lonely-#{System.unique_integer([:positive])}"
      account = AccountsFixtures.organization_fixture(name: handle).account
      Agent.update(ctx.account_ids_pid, &MapSet.put(&1, account.id))

      {:ok, 1} =
        Usage.create_events([
          %{
            "event_id" => "wire-orphan-project",
            "tenant_id" => handle,
            "namespace_id" => "no-such-project",
            "node_id" => "kura-0",
            "region" => "us-east-1",
            "traffic_plane" => "public",
            "direction" => "egress",
            "operation" => "download",
            "protocol" => "http",
            "artifact_kind" => "xcframework",
            "bytes" => 50,
            "request_count" => 1,
            "window_start_unix_seconds" => 1_777_968_000,
            "window_seconds" => 60
          }
        ])

      import Ecto.Query

      assert [%UsageEvent{account_id: a_id, project_id: 0}] =
               Tuist.ClickHouseRepo.all(from(e in UsageEvent, where: e.account_id == ^account.id))

      assert a_id == account.id
    end

    test "rejects batches exceeding @max_events_per_batch" do
      events =
        Enum.map(1..5_001, fn i ->
          %{
            "event_id" => "evt-#{i}",
            "tenant_id" => "acme",
            "namespace_id" => "ios",
            "node_id" => "kura-0",
            "region" => "us-east-1",
            "traffic_plane" => "public",
            "direction" => "egress",
            "operation" => "download",
            "protocol" => "http",
            "artifact_kind" => "xcframework",
            "bytes" => 1,
            "request_count" => 1,
            "window_start_unix_seconds" => 1_777_968_000,
            "window_seconds" => 60
          }
        end)

      assert {:error, :too_many_events} = Usage.create_events(events)
    end
  end

  describe "totals/4" do
    test "splits bytes and requests by direction", ctx do
      account_id = unique_account_id()
      {start_dt, end_dt} = window_span()

      insert_event(%{account_id: account_id, direction: "egress", bytes: 1_000, request_count: 5}, ctx)
      insert_event(%{account_id: account_id, direction: "egress", bytes: 500, request_count: 2}, ctx)
      insert_event(%{account_id: account_id, direction: "ingress", bytes: 200, request_count: 1}, ctx)

      assert %{
               egress: %{bytes: 1_500, request_count: 7},
               ingress: %{bytes: 200, request_count: 1},
               request_count: 8
             } = Usage.totals(account_id, start_dt, end_dt)
    end

    test "returns zeros when there's no traffic in window", ctx do
      account_id = unique_account_id()
      {start_dt, end_dt} = window_span()
      # An event well outside the window to prove it isn't picked up.
      insert_event(
        %{
          account_id: account_id,
          bytes: 9_999,
          request_count: 9,
          window_start: ~N[2026-04-01 00:00:00]
        },
        ctx
      )

      assert %{
               egress: %{bytes: 0, request_count: 0},
               ingress: %{bytes: 0, request_count: 0},
               request_count: 0
             } = Usage.totals(account_id, start_dt, end_dt)
    end

    test "scopes by project_id when supplied", ctx do
      account_id = unique_account_id()
      {start_dt, end_dt} = window_span()

      insert_event(%{account_id: account_id, project_id: 100, bytes: 100, request_count: 1}, ctx)
      insert_event(%{account_id: account_id, project_id: 200, bytes: 700, request_count: 3}, ctx)

      assert %{egress: %{bytes: 100, request_count: 1}} =
               Usage.totals(account_id, start_dt, end_dt, project_id: 100)
    end

    test "is scoped to account_id", ctx do
      mine = unique_account_id()
      other = unique_account_id()
      {start_dt, end_dt} = window_span()

      insert_event(%{account_id: mine, bytes: 100, request_count: 1}, ctx)
      insert_event(%{account_id: other, bytes: 9_999, request_count: 9}, ctx)

      assert %{egress: %{bytes: 100}} = Usage.totals(mine, start_dt, end_dt)
    end
  end

  describe "per_node/4" do
    test "rolls up egress + ingress bytes per (node_id, region)", ctx do
      account_id = unique_account_id()
      {start_dt, end_dt} = window_span()

      insert_event(
        %{account_id: account_id, node_id: "kura-a", region: "us-east-1", direction: "egress", bytes: 1_000, request_count: 4},
        ctx
      )

      insert_event(
        %{account_id: account_id, node_id: "kura-a", region: "us-east-1", direction: "ingress", bytes: 200, request_count: 2},
        ctx
      )

      insert_event(
        %{account_id: account_id, node_id: "kura-b", region: "eu-west-1", direction: "egress", bytes: 400, request_count: 1},
        ctx
      )

      assert [
               %{node_id: "kura-a", region: "us-east-1", egress_bytes: 1_000, ingress_bytes: 200, request_count: 6},
               %{node_id: "kura-b", region: "eu-west-1", egress_bytes: 400, ingress_bytes: 0, request_count: 1}
             ] = Usage.per_node(account_id, start_dt, end_dt)
    end
  end

  describe "traffic_time_series_by_region/4" do
    test "groups bytes by region and fills empty days with zero", ctx do
      account_id = unique_account_id()
      {start_dt, end_dt} = window_span()

      insert_event(
        %{
          account_id: account_id,
          region: "us-east-1",
          bytes: 100,
          window_start: ~N[2026-05-02 09:00:00]
        },
        ctx
      )

      insert_event(
        %{
          account_id: account_id,
          region: "eu-west-1",
          bytes: 50,
          window_start: ~N[2026-05-02 10:00:00]
        },
        ctx
      )

      result = Usage.traffic_time_series_by_region(account_id, start_dt, end_dt, bucket: :day)

      regions = Enum.map(result, & &1.region)
      assert "us-east-1" in regions
      assert "eu-west-1" in regions

      us = Enum.find(result, &(&1.region == "us-east-1"))
      assert us.total == 100
      assert length(us.values) == length(us.dates)
      assert Enum.sum(us.values) == 100
    end

    test "switches to :requests metric when requested", ctx do
      account_id = unique_account_id()
      {start_dt, end_dt} = window_span()

      insert_event(
        %{
          account_id: account_id,
          region: "us-east-1",
          bytes: 999_999,
          request_count: 7,
          window_start: ~N[2026-05-02 09:00:00]
        },
        ctx
      )

      result =
        Usage.traffic_time_series_by_region(account_id, start_dt, end_dt, bucket: :day, metric: :requests)

      us = Enum.find(result, &(&1.region == "us-east-1"))
      # request_count sum, not bytes — proves the metric switch landed.
      assert us.total == 7
    end

    test "filters by direction when supplied", ctx do
      account_id = unique_account_id()
      {start_dt, end_dt} = window_span()

      insert_event(
        %{account_id: account_id, region: "us-east-1", direction: "egress", bytes: 100, window_start: ~N[2026-05-02 09:00:00]},
        ctx
      )

      insert_event(
        %{account_id: account_id, region: "us-east-1", direction: "ingress", bytes: 999, window_start: ~N[2026-05-02 09:00:00]},
        ctx
      )

      result =
        Usage.traffic_time_series_by_region(account_id, start_dt, end_dt, bucket: :day, direction: "egress")

      assert [%{region: "us-east-1", total: 100}] = result
    end

    test "uses hourly buckets when bucket: :hour", ctx do
      account_id = unique_account_id()
      start_dt = ~U[2026-05-02 06:00:00Z]
      end_dt = ~U[2026-05-02 12:00:00Z]

      insert_event(
        %{
          account_id: account_id,
          region: "us-east-1",
          bytes: 50,
          window_start: ~N[2026-05-02 07:00:00]
        },
        ctx
      )

      result = Usage.traffic_time_series_by_region(account_id, start_dt, end_dt, bucket: :hour)

      us = Enum.find(result, &(&1.region == "us-east-1"))
      # 6h–12h inclusive of both ends ⇒ 7 hourly buckets, only one non-zero.
      assert length(us.dates) == 7
      assert us.total == 50
      assert Enum.count(us.values, &(&1 == 50)) == 1
    end
  end

  describe "project_ids_with_usage/1" do
    test "returns distinct project ids with at least one event", ctx do
      account_id = unique_account_id()

      insert_event(%{account_id: account_id, project_id: 11, bytes: 1, request_count: 1}, ctx)
      insert_event(%{account_id: account_id, project_id: 11, bytes: 1, request_count: 1}, ctx)
      insert_event(%{account_id: account_id, project_id: 22, bytes: 1, request_count: 1}, ctx)
      # Unresolved events (project_id == 0) shouldn't appear in the dropdown.
      insert_event(%{account_id: account_id, project_id: 0, bytes: 1, request_count: 1}, ctx)

      assert Enum.sort(Usage.project_ids_with_usage(account_id)) == [11, 22]
    end
  end

  defp unique_account_id, do: System.unique_integer([:positive]) + 1_000_000
end
