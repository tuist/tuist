Code.require_file(
  Path.expand(
    "../../../../priv/repo/migrations/20261125120000_raise_paid_runner_concurrency_defaults.exs",
    __DIR__
  )
)

defmodule Tuist.Repo.Migrations.RaisePaidRunnerConcurrencyDefaultsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query

  alias Tuist.Repo.Migrations.RaisePaidRunnerConcurrencyDefaults, as: Migration
  alias Tuist.Runners.ConcurrencyHistory
  alias Tuist.Runners.ConcurrencyLimit
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  test "raises live paid accounts to the new defaults, keeping anything already higher" do
    pro = paid(:pro, "active", linux: {32, 64}, macos: {16, 48})
    enterprise = paid(:enterprise, "past_due", linux: {32, 64}, macos: {16, 48})
    # Only macOS CPU is above its new default; memory still rises.
    grown = paid(:pro, "active", linux: {96, 96}, macos: {72, 72})
    lapsed = paid(:pro, "canceled", linux: {32, 64}, macos: {16, 48})
    air = AccountsFixtures.account_fixture()

    # excellent_migrations:safety-assured-for-next-line operation_query
    Repo.query!("SELECT set_config('tuist.runner_concurrency_source', 'plan', true)")
    # excellent_migrations:safety-assured-for-next-line operation_query
    Repo.query!(Migration.raise_statement())

    for account <- [pro, enterprise] do
      assert limits(account) == %{linux: {64, 128}, macos: {48, 144}}
    end

    assert limits(grown) == %{linux: {96, 128}, macos: {72, 144}}
    assert limits(lapsed) == %{linux: {32, 64}, macos: {16, 48}}
    assert limits(air) == %{linux: {16, 64}, macos: {16, 48}}

    # The raise is recorded as a plan grant.
    latest =
      ConcurrencyHistory
      |> where([h], h.account_id == ^pro.id and h.platform == :macos)
      |> order_by([h], desc: h.id)
      |> limit(1)
      # excellent_migrations:safety-assured-for-next-line operation_one
      |> Repo.one()

    assert %{vcpus: 48, memory_gb: 144, source: "plan"} = latest
  end

  defp paid(plan, status, limits) do
    account = AccountsFixtures.account_fixture()
    BillingFixtures.subscription_fixture(account_id: account.id, plan: plan, status: status)

    for {platform, {vcpus, memory_gb}} <- limits do
      ConcurrencyLimit
      |> where([l], l.account_id == ^account.id and l.platform == ^to_string(platform))
      # excellent_migrations:safety-assured-for-next-line operation_update
      |> Repo.update_all(set: [vcpus: vcpus, memory_gb: memory_gb])
    end

    account
  end

  defp limits(account) do
    ConcurrencyLimit
    |> where([l], l.account_id == ^account.id)
    # excellent_migrations:safety-assured-for-next-line operation_all
    |> Repo.all()
    |> Map.new(&{&1.platform, {&1.vcpus, &1.memory_gb}})
  end
end
