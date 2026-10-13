defmodule Tuist.Kura.UsageTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query
  import Mimic

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Kura.Demand
  alias Tuist.Kura.Usage
  alias Tuist.Kura.UsageEvent
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup :set_mimic_from_context

  test "failed ingestion does not refresh managed demand" do
    account = AccountsFixtures.user_fixture().account
    event = wire_event(%{"tenant_id" => account.name, "window_start_unix_seconds" => System.system_time(:second)})
    expect(IngestRepo, :insert_all, fn UsageEvent, _ -> raise "ingest unavailable" end)
    reject(Demand, :record, 1)
    assert_raise RuntimeError, "ingest unavailable", fn -> Usage.create_events([event]) end
  end

  test "fresh managed traffic refreshes demand once per account" do
    account = AccountsFixtures.user_fixture().account
    expect(Demand, :record, fn id -> assert id == account.id end)
    event = wire_event(%{"tenant_id" => account.name, "window_start_unix_seconds" => System.system_time(:second) - 60})
    assert {:ok, 2} = Usage.create_events([event, %{event | "event_id" => "another-event"}])
  end

  test "replayed, future, empty, peer and self-hosted traffic do not keep managed capacity warm" do
    account = AccountsFixtures.user_fixture().account
    reject(Demand, :record, 1)
    now = System.system_time(:second)
    event = wire_event(%{"tenant_id" => account.name, "window_start_unix_seconds" => now})

    events = [
      %{event | "window_start_unix_seconds" => now - 3600},
      %{event | "window_start_unix_seconds" => now + 3600},
      %{event | "request_count" => 0},
      %{event | "traffic_plane" => "peer"}
    ]

    assert {:ok, 4} = Usage.create_events(events)
    assert {:ok, 1} = Usage.create_events([event], account)
  end

  defp insert_event(attrs) do
    base = %{
      event_id: "evt-#{System.unique_integer([:positive])}",
      account_id: Map.fetch!(attrs, :account_id),
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

  defp wire_event(overrides) do
    Map.merge(
      %{
        "event_id" => "wire-#{System.unique_integer([:positive])}",
        "tenant_id" => "acme",
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
      },
      overrides
    )
  end

  defp window_span do
    {
      ~U[2026-05-01 00:00:00Z],
      ~U[2026-05-08 00:00:00Z]
    }
  end

  defp unique_account_id, do: System.unique_integer([:positive]) + 1_000_000

  describe "create_events/1" do
    test "resolves tenant and namespace handles to account and project ids regardless of casing" do
      account = AccountsFixtures.organization_fixture(name: "Acme-#{System.unique_integer([:positive])}").account
      project = ProjectsFixtures.project_fixture(account: account, name: "ios")

      {:ok, 1} =
        Usage.create_events([
          wire_event(%{
            "event_id" => "wire-1",
            "tenant_id" => String.downcase(account.name),
            "namespace_id" => "ios"
          })
        ])

      assert [%UsageEvent{account_id: a_id, project_id: p_id, bytes: 100}] =
               ClickHouseRepo.all(from(e in UsageEvent, where: e.account_id == ^account.id))

      assert a_id == account.id
      assert p_id == project.id
    end

    test "matches the namespace to a project regardless of casing" do
      account = AccountsFixtures.organization_fixture().account
      project = ProjectsFixtures.project_fixture(account: account, name: "ios")
      event_id = "wire-namespace-case-#{account.id}"

      {:ok, 1} =
        Usage.create_events([
          wire_event(%{
            "event_id" => event_id,
            "tenant_id" => account.name,
            "namespace_id" => "iOS"
          })
        ])

      assert [%UsageEvent{project_id: project_id}] =
               ClickHouseRepo.all(from(e in UsageEvent, where: e.event_id == ^event_id))

      assert project_id == project.id
    end

    test "keeps the account when the namespace names no project" do
      account = AccountsFixtures.organization_fixture().account

      {:ok, 1} =
        Usage.create_events([
          wire_event(%{
            "event_id" => "wire-orphan-project",
            "tenant_id" => account.name,
            "namespace_id" => "no-such-project",
            "bytes" => 50
          })
        ])

      assert [%UsageEvent{account_id: a_id, project_id: 0}] =
               ClickHouseRepo.all(from(e in UsageEvent, where: e.account_id == ^account.id))

      assert a_id == account.id
    end

    test "rejects batches exceeding @max_events_per_batch" do
      events = Enum.map(1..5_001, fn i -> wire_event(%{"event_id" => "evt-#{i}"}) end)

      assert {:error, :too_many_events} = Usage.create_events(events)
    end
  end

  describe "create_events/2" do
    test "attributes a self-hosted node's events to the account its credential authenticated as" do
      account = AccountsFixtures.organization_fixture(name: "Acme-#{System.unique_integer([:positive])}").account
      project = ProjectsFixtures.project_fixture(account: account, name: "ios")
      event_id = "wire-self-hosted-#{account.id}"

      {:ok, 1} =
        Usage.create_events(
          [wire_event(%{"event_id" => event_id, "tenant_id" => String.downcase(account.name)})],
          account
        )

      assert [%UsageEvent{account_id: a_id, project_id: p_id}] =
               ClickHouseRepo.all(from(e in UsageEvent, where: e.event_id == ^event_id))

      assert a_id == account.id
      assert p_id == project.id
    end
  end

  describe "totals/4" do
    test "splits bytes and requests by direction" do
      account_id = unique_account_id()
      {start_dt, end_dt} = window_span()

      insert_event(%{account_id: account_id, direction: "egress", bytes: 1_000, request_count: 5})
      insert_event(%{account_id: account_id, direction: "egress", bytes: 500, request_count: 2})
      insert_event(%{account_id: account_id, direction: "ingress", bytes: 200, request_count: 1})

      assert %{
               egress: %{bytes: 1_500, request_count: 7},
               ingress: %{bytes: 200, request_count: 1},
               request_count: 8
             } = Usage.totals(account_id, start_dt, end_dt)
    end

    test "returns zeros when there's no traffic in window" do
      account_id = unique_account_id()
      {start_dt, end_dt} = window_span()
      # An event well outside the window to prove it isn't picked up.
      insert_event(%{
        account_id: account_id,
        bytes: 9_999,
        request_count: 9,
        window_start: ~N[2026-04-01 00:00:00]
      })

      assert %{
               egress: %{bytes: 0, request_count: 0},
               ingress: %{bytes: 0, request_count: 0},
               request_count: 0
             } = Usage.totals(account_id, start_dt, end_dt)
    end

    test "scopes by project_id when supplied" do
      account_id = unique_account_id()
      {start_dt, end_dt} = window_span()

      insert_event(%{account_id: account_id, project_id: 100, bytes: 100, request_count: 1})
      insert_event(%{account_id: account_id, project_id: 200, bytes: 700, request_count: 3})

      assert %{egress: %{bytes: 100, request_count: 1}} =
               Usage.totals(account_id, start_dt, end_dt, project_id: 100)
    end

    test "is scoped to account_id" do
      mine = unique_account_id()
      other = unique_account_id()
      {start_dt, end_dt} = window_span()

      insert_event(%{account_id: mine, bytes: 100, request_count: 1})
      insert_event(%{account_id: other, bytes: 9_999, request_count: 9})

      assert %{egress: %{bytes: 100}} = Usage.totals(mine, start_dt, end_dt)
    end

    # Kura delivers usage events at-least-once: a network blip between the
    # node and the control plane can land the same event_id twice. The query
    # path has to dedupe by event_id so retries don't inflate the customer's
    # bill.
    test "dedupes duplicate event_ids via argMax on inserted_at" do
      account_id = unique_account_id()
      {start_dt, end_dt} = window_span()
      event_id = "duplicate-#{System.unique_integer([:positive])}"

      insert_event(%{
        account_id: account_id,
        event_id: event_id,
        direction: "egress",
        bytes: 100,
        request_count: 1,
        inserted_at: ~N[2026-05-01 12:00:00]
      })

      # Same event_id, later inserted_at — should win the argMax tiebreak.
      insert_event(%{
        account_id: account_id,
        event_id: event_id,
        direction: "egress",
        bytes: 100,
        request_count: 1,
        inserted_at: ~N[2026-05-01 12:05:00]
      })

      assert %{egress: %{bytes: 100, request_count: 1}, request_count: 1} =
               Usage.totals(account_id, start_dt, end_dt)
    end

    test "returns trend percentage vs the equivalent previous window" do
      account_id = unique_account_id()
      start_dt = ~U[2026-05-08 00:00:00Z]
      end_dt = ~U[2026-05-15 00:00:00Z]

      # Current window: 200 bytes egress.
      insert_event(%{
        account_id: account_id,
        direction: "egress",
        bytes: 200,
        request_count: 4,
        window_start: ~N[2026-05-10 00:00:00]
      })

      # Previous window (same 7-day length, ending where current starts): 100 bytes.
      insert_event(%{
        account_id: account_id,
        direction: "egress",
        bytes: 100,
        request_count: 2,
        window_start: ~N[2026-05-03 00:00:00]
      })

      result = Usage.totals(account_id, start_dt, end_dt)

      # 200 vs 100 = +100% growth.
      assert result.egress.bytes == 200
      assert result.egress.bytes_trend == 100.0
      assert result.request_count == 4
      assert result.request_count_trend == 100.0
    end
  end

  describe "per_region/4" do
    test "rolls up egress + ingress bytes per region across nodes" do
      account_id = unique_account_id()
      {start_dt, end_dt} = window_span()

      insert_event(%{
        account_id: account_id,
        node_id: "kura-a",
        region: "us-east-1",
        direction: "egress",
        bytes: 1_000,
        request_count: 4
      })

      insert_event(%{
        account_id: account_id,
        node_id: "kura-b",
        region: "us-east-1",
        direction: "ingress",
        bytes: 200,
        request_count: 2
      })

      insert_event(%{
        account_id: account_id,
        node_id: "kura-c",
        region: "eu-west-1",
        direction: "egress",
        bytes: 400,
        request_count: 1
      })

      assert [
               %{region: "us-east-1", egress_bytes: 1_000, ingress_bytes: 200, request_count: 6},
               %{region: "eu-west-1", egress_bytes: 400, ingress_bytes: 0, request_count: 1}
             ] = Usage.per_region(account_id, start_dt, end_dt)
    end
  end

  describe "traffic_time_series_by_region/4" do
    test "groups bytes by region and fills empty days with zero" do
      account_id = unique_account_id()
      {start_dt, end_dt} = window_span()

      insert_event(%{
        account_id: account_id,
        region: "us-east-1",
        bytes: 100,
        window_start: ~N[2026-05-02 09:00:00]
      })

      insert_event(%{
        account_id: account_id,
        region: "eu-west-1",
        bytes: 50,
        window_start: ~N[2026-05-02 10:00:00]
      })

      result = Usage.traffic_time_series_by_region(account_id, start_dt, end_dt, bucket: :day)

      regions = Enum.map(result, & &1.region)
      assert "us-east-1" in regions
      assert "eu-west-1" in regions

      us = Enum.find(result, &(&1.region == "us-east-1"))
      assert us.total == 100
      assert length(us.values) == length(us.dates)
      assert Enum.sum(us.values) == 100
    end

    test "switches to :requests metric when requested" do
      account_id = unique_account_id()
      {start_dt, end_dt} = window_span()

      insert_event(%{
        account_id: account_id,
        region: "us-east-1",
        bytes: 999_999,
        request_count: 7,
        window_start: ~N[2026-05-02 09:00:00]
      })

      result =
        Usage.traffic_time_series_by_region(account_id, start_dt, end_dt, bucket: :day, metric: :requests)

      us = Enum.find(result, &(&1.region == "us-east-1"))
      # request_count sum, not bytes — proves the metric switch landed.
      assert us.total == 7
    end

    test "filters by direction when supplied" do
      account_id = unique_account_id()
      {start_dt, end_dt} = window_span()

      insert_event(%{
        account_id: account_id,
        region: "us-east-1",
        direction: "egress",
        bytes: 100,
        window_start: ~N[2026-05-02 09:00:00]
      })

      insert_event(%{
        account_id: account_id,
        region: "us-east-1",
        direction: "ingress",
        bytes: 999,
        window_start: ~N[2026-05-02 09:00:00]
      })

      result =
        Usage.traffic_time_series_by_region(account_id, start_dt, end_dt,
          bucket: :day,
          direction: "egress"
        )

      assert [%{region: "us-east-1", total: 100}] = result
    end

    test "uses hourly buckets when bucket: :hour" do
      account_id = unique_account_id()
      start_dt = ~U[2026-05-02 06:00:00Z]
      end_dt = ~U[2026-05-02 12:00:00Z]

      insert_event(%{
        account_id: account_id,
        region: "us-east-1",
        bytes: 50,
        window_start: ~N[2026-05-02 07:00:00]
      })

      result = Usage.traffic_time_series_by_region(account_id, start_dt, end_dt, bucket: :hour)

      us = Enum.find(result, &(&1.region == "us-east-1"))
      # 6h–12h inclusive of both ends ⇒ 7 hourly buckets, only one non-zero.
      assert length(us.dates) == 7
      assert us.total == 50
      assert Enum.count(us.values, &(&1 == 50)) == 1
    end
  end

  describe "project_ids_with_usage/1" do
    test "returns distinct project ids with at least one event" do
      account_id = unique_account_id()

      insert_event(%{account_id: account_id, project_id: 11, bytes: 1, request_count: 1})
      insert_event(%{account_id: account_id, project_id: 11, bytes: 1, request_count: 1})
      insert_event(%{account_id: account_id, project_id: 22, bytes: 1, request_count: 1})
      # Unresolved events (project_id == 0) shouldn't appear in the dropdown.
      insert_event(%{account_id: account_id, project_id: 0, bytes: 1, request_count: 1})

      assert Enum.sort(Usage.project_ids_with_usage(account_id)) == [11, 22]
    end
  end
end
