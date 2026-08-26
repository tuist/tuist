defmodule Tuist.Kura.OriginsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Accounts
  alias Tuist.Kura.OriginRollup
  alias Tuist.Kura.Origins
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

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
  end

  describe "upsert_many/1" do
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

  defp rollup(account, origin) do
    Repo.get_by(OriginRollup, account_id: account.id, origin: origin, date: Date.utc_today())
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
