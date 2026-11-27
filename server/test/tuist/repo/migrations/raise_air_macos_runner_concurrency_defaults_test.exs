Code.require_file(
  Path.expand(
    "../../../../priv/repo/migrations/20261127120000_raise_air_macos_runner_concurrency_defaults.exs",
    __DIR__
  )
)

defmodule Tuist.Repo.Migrations.RaiseAirMacosRunnerConcurrencyDefaultsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query

  alias Tuist.Repo.Migrations.RaiseAirMacosRunnerConcurrencyDefaults, as: Migration
  alias Tuist.Runners.ConcurrencyHistory
  alias Tuist.Runners.ConcurrencyLimit
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  test "new accounts start with two baseline macOS guests" do
    assert limits(AccountsFixtures.account_fixture()) == %{linux: {16, 64}, macos: {16, 48}}
  end

  test "raises Air macOS limits to the new default, keeping anything already higher" do
    air = account(nil, linux: {16, 64}, macos: {8, 24})
    # Only macOS CPU is above its new default; memory still rises.
    grown = account(nil, linux: {16, 64}, macos: {24, 32})
    higher = account(nil, linux: {16, 64}, macos: {32, 96})
    lapsed = account({:pro, "canceled"}, linux: {16, 64}, macos: {8, 24})
    # A live paid account below the Air default is left to the paid plan's own grants.
    paid = account({:pro, "active"}, linux: {64, 128}, macos: {8, 24})

    # excellent_migrations:safety-assured-for-next-line operation_query
    Repo.query!("SELECT set_config('tuist.runner_concurrency_source', 'plan', true)")
    # excellent_migrations:safety-assured-for-next-line operation_query
    Repo.query!(Migration.raise_statement())

    assert limits(air) == %{linux: {16, 64}, macos: {16, 48}}
    assert limits(grown) == %{linux: {16, 64}, macos: {24, 48}}
    assert limits(higher) == %{linux: {16, 64}, macos: {32, 96}}
    assert limits(lapsed) == %{linux: {16, 64}, macos: {16, 48}}
    assert limits(paid) == %{linux: {64, 128}, macos: {8, 24}}

    # The raise is recorded as a plan grant.
    latest =
      ConcurrencyHistory
      |> where([h], h.account_id == ^air.id and h.platform == :macos)
      |> order_by([h], desc: h.id)
      |> limit(1)
      # excellent_migrations:safety-assured-for-next-line operation_one
      |> Repo.one()

    assert %{vcpus: 16, memory_gb: 48, source: "plan"} = latest
  end

  defp account(subscription, limits) do
    account = AccountsFixtures.account_fixture()

    with {plan, status} <- subscription do
      BillingFixtures.subscription_fixture(account_id: account.id, plan: plan, status: status)
    end

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
