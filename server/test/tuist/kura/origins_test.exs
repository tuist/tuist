defmodule Tuist.Kura.OriginsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.IngestRepo
  alias Tuist.Kura.OriginRollup
  alias Tuist.Kura.Origins
  alias Tuist.Kura.UsageEvent
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :set_mimic_from_context

  setup do
    user = AccountsFixtures.user_fixture()

    %{account: Accounts.get_account_from_user(user)}
  end

  describe "record_run/2 and record_demand/2" do
    test "counts a run against the account's day and origin", %{account: account} do
      Origins.record_run(account.id, "FR")
      Origins.record_run(account.id, "FR")

      assert %OriginRollup{run_count: 2, demand_count: 0, date: date} = rollup(account, "FR")
      assert date == Date.utc_today()
    end

    test "counts resolutions separately from runs", %{account: account} do
      Origins.record_run(account.id, "FR")
      Origins.record_demand(account.id, "FR")

      assert %OriginRollup{run_count: 1, demand_count: 1} = rollup(account, "FR")
    end

    test "keeps origins apart", %{account: account} do
      Origins.record_run(account.id, "FR")
      Origins.record_run(account.id, "US-VA")

      assert %OriginRollup{run_count: 1} = rollup(account, "FR")
      assert %OriginRollup{run_count: 1} = rollup(account, "US-VA")
    end

    test "accepts what the request path resolved, attributed or not", %{account: account} do
      Origins.record_run(account.id, {:ok, "FR"})
      Origins.record_demand(account.id, {:error, :no_location})

      assert %OriginRollup{run_count: 1, demand_count: 0} = rollup(account, "FR")
      assert Repo.aggregate(OriginRollup, :count) == 1
    end

    test "counts an unattributed request nowhere", %{account: account} do
      # An unattributed run is missing evidence. Counting it as the default
      # would let requests nobody could locate vote on where servers go.
      Origins.record_run(account.id, nil)
      Origins.record_demand(account.id, nil)

      assert Repo.aggregate(OriginRollup, :count) == 0
    end

    test "ignores a request with no account behind it" do
      Origins.record_run(nil, "FR")

      assert Repo.aggregate(OriginRollup, :count) == 0
    end

    test "ignores late signals for a deleted account", %{account: account} do
      Repo.delete!(account)

      assert :ok = Origins.record_run(account.id, "FR")
      assert :ok = Origins.record_demand(account.id, "FR")
      assert Repo.aggregate(OriginRollup, :count) == 0
    end
  end

  describe "upsert_many/1" do
    test "inserts rows in account, origin and date order", %{account: first} do
      second = AccountsFixtures.account_fixture()
      earlier = ~D[2025-12-31]
      later = ~D[2026-01-01]

      rows = [
        Map.put(row(second, "FR", 1, 0), :date, earlier),
        Map.put(row(first, "US-VA", 2, 1), :date, earlier),
        Map.put(row(first, "FR", 3, 2), :date, later),
        Map.put(row(first, "FR", 4, 3), :date, earlier)
      ]

      test_pid = self()

      stub(Repo, :insert_all, fn schema, rows, opts ->
        send(test_pid, {:insert_all, schema, rows})
        Mimic.call_original(Repo, :insert_all, [schema, rows, opts])
      end)

      assert {:ok, 4} = Origins.upsert_many(rows)
      assert_received {:insert_all, OriginRollup, inserted_rows}

      assert Enum.map(inserted_rows, &{&1.account_id, &1.origin, &1.date}) == [
               {first.id, "FR", earlier},
               {first.id, "FR", later},
               {first.id, "US-VA", earlier},
               {second.id, "FR", earlier}
             ]

      assert Repo.aggregate(OriginRollup, :count) == 4
    end

    test "adds to what the day already holds rather than replacing it", %{account: account} do
      Origins.upsert_many([row(account, "FR", 3, 1)])
      Origins.upsert_many([row(account, "FR", 4, 2)])

      assert %OriginRollup{run_count: 7, demand_count: 3} = rollup(account, "FR")
    end

    test "keeps a row per account, origin and day", %{account: account} do
      yesterday = Date.add(Date.utc_today(), -1)

      Origins.upsert_many([row(account, "FR", 1, 0), Map.put(row(account, "FR", 5, 0), :date, yesterday)])

      assert Repo.aggregate(OriginRollup, :count) == 2
    end

    test "skips deleted accounts while preserving other accounts' counts", %{account: account} do
      deleted_account = AccountsFixtures.account_fixture()
      Origins.upsert_many([row(account, "FR", 3, 1)])
      rows = [row(deleted_account, "FR", 10, 5), row(account, "FR", 4, 2), row(account, "US-VA", 1, 1)]
      Repo.delete!(deleted_account)

      assert {:ok, 2} = Origins.upsert_many(rows)

      assert %OriginRollup{run_count: 7, demand_count: 3} = rollup(account, "FR")
      assert %OriginRollup{run_count: 1, demand_count: 1} = rollup(account, "US-VA")
      assert Repo.aggregate(OriginRollup, :count) == 2
    end

    test "returns zero when every account in the batch has been deleted", %{account: account} do
      rows = [row(account, "FR", 3, 1), row(account, "US-VA", 2, 4)]
      Repo.delete!(account)

      assert {:ok, 0} = Origins.upsert_many(rows)
      assert Repo.aggregate(OriginRollup, :count) == 0
    end
  end

  describe "rollups_since/2" do
    test "returns the account's rows from the date onwards, grouped by account", %{account: account} do
      today = Date.utc_today()

      Origins.upsert_many([
        row(account, "FR", 1, 0),
        Map.put(row(account, "FR", 5, 0), :date, Date.add(today, -10))
      ])

      grouped = Origins.rollups_since([account.id], Date.add(today, -5))

      assert [%OriginRollup{run_count: 1}] = Map.fetch!(grouped, account.id)
    end
  end

  describe "traffic_mix/2" do
    test "reports each origin with the region it maps to, busiest first", %{account: account} do
      Origins.upsert_many([row(account, "FR", 10, 2), row(account, "US-OR", 30, 1)])

      assert [
               %{origin: "US-OR", region: "us-west", run_count: 30, demand_count: 1, hit_count: 0},
               %{origin: "FR", region: "eu-west", run_count: 10, demand_count: 2}
             ] = Origins.traffic_mix(account, 14)
    end

    test "leaves out what fell outside the window", %{account: account} do
      old = Date.add(Date.utc_today(), -20)

      Origins.upsert_many([row(account, "FR", 1, 0), Map.put(row(account, "SG", 99, 0), :date, old)])

      assert [%{origin: "FR"}] = Origins.traffic_mix(account, 14)
    end

    test "is empty for an account nothing has been attributed to", %{account: account} do
      assert Origins.traffic_mix(account, 14) == []
    end
  end

  describe "refresh_hits/1" do
    test "writes the hits public regions served each origin, leaving runs alone", %{account: account} do
      date = unique_date()
      Origins.upsert_many([Map.put(row(account, "FR", 3, 1), :date, date)])
      insert_usage(account.id, "hits-1-#{account.id}", "eu-west", "FR", "egress", 40, date)
      insert_usage(account.id, "hits-2-#{account.id}", "eu-west", "FR", "egress", 2, date)
      insert_usage(account.id, "hits-3-#{account.id}", "eu-west", "FR", "ingress", 500, date)
      insert_usage(account.id, "hits-4-#{account.id}", "us-east", "US-VA", "egress", 7, date)

      assert {:ok, 2} = Origins.refresh_hits([date])

      assert %OriginRollup{run_count: 3, demand_count: 1, hit_count: 42} = rollup(account, "FR", date)
      assert %OriginRollup{run_count: 0, demand_count: 0, hit_count: 7} = rollup(account, "US-VA", date)
    end

    test "converges on a day refreshed again rather than adding to it", %{account: account} do
      date = unique_date()
      insert_usage(account.id, "again-1-#{account.id}", "eu-west", "FR", "egress", 40, date)
      {:ok, 1} = Origins.refresh_hits([date])
      insert_usage(account.id, "again-2-#{account.id}", "eu-west", "FR", "egress", 2, date)

      {:ok, 1} = Origins.refresh_hits([date])

      assert %OriginRollup{hit_count: 42} = rollup(account, "FR", date)
    end

    test "leaves out private runner caches and hits nobody attributed", %{account: account} do
      date = unique_date()
      insert_usage(account.id, "private-#{account.id}", "scw-fr-par-runners", "FR", "egress", 40, date)
      insert_usage(account.id, "unattributed-#{account.id}", "eu-west", "", "egress", 40, date)

      assert {:ok, 0} = Origins.refresh_hits([date])
      assert Repo.aggregate(OriginRollup, :count) == 0
    end
  end

  # ClickHouse rows survive across tests, so each test claims its own day.
  defp unique_date, do: Date.add(~D[2031-01-01], rem(System.unique_integer([:positive]), 20_000))

  defp insert_usage(account_id, event_id, region, origin, direction, request_count, date) do
    window_start = NaiveDateTime.new!(date, ~T[10:00:00])

    IngestRepo.insert_all(UsageEvent, [
      %{
        event_id: event_id,
        account_id: account_id,
        project_id: 0,
        node_id: "kura-0",
        region: region,
        traffic_plane: "public",
        direction: direction,
        operation: if(direction == "egress", do: "download", else: "upload"),
        protocol: "grpc",
        artifact_kind: "reapi",
        bytes: request_count * 1_024,
        request_count: request_count,
        origin: origin,
        window_start: window_start,
        window_seconds: 60,
        inserted_at: window_start
      }
    ])
  end

  defp rollup(account, origin) do
    Repo.get_by(OriginRollup, account_id: account.id, origin: origin, date: Date.utc_today())
  end

  defp rollup(account, origin, date) do
    Repo.get_by(OriginRollup, account_id: account.id, origin: origin, date: date)
  end

  defp row(account, origin, runs, demand) do
    %{
      account_id: account.id,
      origin: origin,
      date: Date.utc_today(),
      run_count: runs,
      demand_count: demand
    }
  end
end
