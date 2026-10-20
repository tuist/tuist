defmodule Tuist.Kura.OriginsBufferTest do
  # The buffer is shared across processes, so these tests run after async cases.
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Environment
  alias Tuist.Kura.OriginRollup
  alias Tuist.Kura.Origins
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :set_mimic_from_context

  setup do
    stub(Environment, :kura_demand_write_through_repo?, fn -> false end)
    Origins.flush()
    :ok
  end

  test "flush skips an account deleted after recording and continues counting surviving accounts" do
    account = AccountsFixtures.account_fixture()
    deleted_account = AccountsFixtures.account_fixture()

    Origins.record_run(deleted_account.id, "FR")
    Origins.record_demand(deleted_account.id, "FR")
    Origins.record_run(account.id, "FR")
    Origins.record_demand(account.id, "FR")
    Repo.delete!(deleted_account)

    assert Repo.aggregate(OriginRollup, :count) == 0
    assert {:ok, 1} = Origins.flush()
    assert {:ok, 0} = Origins.flush()
    assert %OriginRollup{run_count: 1, demand_count: 1} = Repo.get_by!(OriginRollup, account_id: account.id)

    Origins.record_run(account.id, "FR")

    assert {:ok, 1} = Origins.flush()
    assert %OriginRollup{run_count: 2, demand_count: 1} = Repo.get_by!(OriginRollup, account_id: account.id)
    assert Repo.aggregate(OriginRollup, :count) == 1
  end
end
