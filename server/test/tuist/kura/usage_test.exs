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
  setup :verify_on_exit!

  test "failed ingestion does not refresh managed demand" do
    account = AccountsFixtures.user_fixture().account
    event = wire_event(%{"tenant_id" => account.name, "window_start_unix_seconds" => System.system_time(:second)})
    expect(IngestRepo, :insert_all, fn UsageEvent, _ -> raise "ingest unavailable" end)
    reject(Demand, :record, 3)
    assert_raise RuntimeError, "ingest unavailable", fn -> Usage.create_events([event]) end
  end

  test "fresh managed traffic refreshes demand and the traffic clock once per account" do
    account = AccountsFixtures.user_fixture().account
    expect(Demand, :record, fn id, nil, [traffic: true] -> assert id == account.id end)
    event = wire_event(%{"tenant_id" => account.name, "window_start_unix_seconds" => System.system_time(:second) - 60})
    assert {:ok, 2} = Usage.create_events([event, %{event | "event_id" => "another-event"}])
  end

  test "replayed, future, empty, peer and self-hosted traffic do not keep managed capacity warm" do
    account = AccountsFixtures.user_fixture().account
    reject(Demand, :record, 3)
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

    test "keeps the origin a managed node attributed a rollup to, and drops one that is not a label" do
      account = AccountsFixtures.organization_fixture().account

      {:ok, 3} =
        Usage.create_events([
          wire_event(%{"event_id" => "origin-#{account.id}-1", "tenant_id" => account.name, "origin" => "US-IL"}),
          wire_event(%{"event_id" => "origin-#{account.id}-2", "tenant_id" => account.name, "origin" => "not a label"}),
          wire_event(%{"event_id" => "origin-#{account.id}-3", "tenant_id" => account.name})
        ])

      origins =
        from(e in UsageEvent, where: e.account_id == ^account.id, select: {e.event_id, e.origin})
        |> ClickHouseRepo.all()
        |> Map.new()

      assert origins == %{
               "origin-#{account.id}-1" => "US-IL",
               "origin-#{account.id}-2" => "",
               "origin-#{account.id}-3" => ""
             }
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

    test "drops the origin a self-hosted node reports" do
      account = AccountsFixtures.organization_fixture().account
      event_id = "wire-self-hosted-origin-#{account.id}"

      {:ok, 1} =
        Usage.create_events([wire_event(%{"event_id" => event_id, "origin" => "US-IL"})], account)

      assert [""] = ClickHouseRepo.all(from(e in UsageEvent, where: e.event_id == ^event_id, select: e.origin))
    end
  end
end
