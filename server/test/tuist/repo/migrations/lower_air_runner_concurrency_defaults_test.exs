Code.require_file(
  Path.expand(
    "../../../../priv/repo/migrations/20261117160000_lower_air_runner_concurrency_defaults.exs",
    __DIR__
  )
)

defmodule Tuist.Repo.Migrations.LowerAirRunnerConcurrencyDefaultsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query

  alias Tuist.Repo.Migrations.LowerAirRunnerConcurrencyDefaults, as: Migration
  alias Tuist.Runners.ConcurrencyLimit
  alias Tuist.Runners.Profile
  alias Tuist.Runners.RunnerSession
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  test "lowers only idle Air accounts still on the old defaults" do
    idle = old_defaults(AccountsFixtures.account_fixture())

    pro = AccountsFixtures.account_fixture()
    BillingFixtures.subscription_fixture(account_id: pro.id, plan: :pro)

    lapsed = old_defaults(AccountsFixtures.account_fixture())
    BillingFixtures.subscription_fixture(account_id: lapsed.id, plan: :pro, status: "canceled")

    active = old_defaults(AccountsFixtures.account_fixture())
    session(active, DateTime.add(DateTime.utc_now(), -1, :day))

    stale = old_defaults(AccountsFixtures.account_fixture())
    session(stale, DateTime.add(DateTime.utc_now(), -31, :day))

    on_trial = old_defaults(AccountsFixtures.account_fixture())
    # excellent_migrations:safety-assured-for-next-line operation_update
    Repo.update!(Ecto.Changeset.change(on_trial, runner_trial_started_at: DateTime.utc_now(:second)))

    large_profile = old_defaults(AccountsFixtures.account_fixture())
    profile(large_profile, vcpus: 16, memory_gb: 48)

    customized = AccountsFixtures.account_fixture()
    set_limit(customized, :linux, 48, 96)
    set_limit(customized, :macos, 16, 49)

    # excellent_migrations:safety-assured-for-next-line operation_query
    Repo.query!(Migration.lower_statement())

    for account <- [idle, lapsed, stale] do
      assert limits(account) == %{linux: {16, 64}, macos: {8, 24}}
    end

    for account <- [pro, active, on_trial] do
      assert limits(account) == %{linux: {32, 64}, macos: {16, 48}}
    end

    # Its Linux limit has nothing to keep it; macOS must still admit its profile.
    assert limits(large_profile) == %{linux: {16, 64}, macos: {16, 48}}
    assert limits(customized) == %{linux: {48, 96}, macos: {16, 49}}
  end

  defp old_defaults(account) do
    set_limit(account, :linux, 32, 64)
    set_limit(account, :macos, 16, 48)
    account
  end

  defp set_limit(account, platform, vcpus, memory_gb) do
    ConcurrencyLimit
    |> where([l], l.account_id == ^account.id and l.platform == ^to_string(platform))
    # excellent_migrations:safety-assured-for-next-line operation_update
    |> Repo.update_all(set: [vcpus: vcpus, memory_gb: memory_gb])
  end

  defp limits(account) do
    ConcurrencyLimit
    |> where([l], l.account_id == ^account.id)
    # excellent_migrations:safety-assured-for-next-line operation_all
    |> Repo.all()
    |> Map.new(&{&1.platform, {&1.vcpus, &1.memory_gb}})
  end

  defp session(account, started_at) do
    # excellent_migrations:safety-assured-for-next-line operation_insert
    Repo.insert!(%RunnerSession{
      account_id: account.id,
      workflow_job_id: System.unique_integer([:positive]),
      fleet_name: "macos-pool",
      platform: :macos,
      vcpus: 8,
      memory_gb: 24,
      started_at: started_at,
      ended_at: DateTime.add(started_at, 600, :second)
    })
  end

  defp profile(account, attrs) do
    attrs =
      Map.merge(
        %{
          account_id: account.id,
          name: "lower-#{System.unique_integer([:positive])}",
          platform: :macos,
          xcode_version: "27.0"
        },
        Map.new(attrs)
      )

    # excellent_migrations:safety-assured-for-next-line operation_insert
    Repo.insert!(struct!(Profile, attrs))
  end
end
