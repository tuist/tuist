Code.require_file(
  Path.expand("../../../../priv/repo/migrations/20261028180000_add_sandbox_concurrency_limits.exs", __DIR__)
)

defmodule Tuist.Repo.Migrations.AddSandboxConcurrencyLimitsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Repo
  alias Tuist.Repo.Migrations.AddSandboxConcurrencyLimits
  alias Tuist.Runners.Concurrency
  alias TuistTestSupport.Fixtures.AccountsFixtures

  test "copies each account's Linux limits, preserving CI settings and defaults" do
    account = AccountsFixtures.account_fixture()
    default = AccountsFixtures.account_fixture()

    {:ok, _} =
      Concurrency.update_limits(account, %{
        runner_linux_vcpus_limit: 48,
        runner_linux_memory_gb_limit: 80,
        runner_macos_vcpus_limit: 18,
        runner_macos_memory_gb_limit: 42
      })

    # Same SQL as the migration, in the sandbox transaction.
    # excellent_migrations:safety-assured-for-next-line operation_query
    Repo.query!(AddSandboxConcurrencyLimits.backfill_statement())
    # excellent_migrations:safety-assured-for-next-line operation_reload
    copied = Repo.reload!(account)
    assert {copied.sandbox_vcpus_limit, copied.sandbox_memory_gb_limit} == {48, 80}
    # excellent_migrations:safety-assured-for-next-line operation_reload
    unchanged = Repo.reload!(default)
    assert {unchanged.sandbox_vcpus_limit, unchanged.sandbox_memory_gb_limit} == {32, 64}
    assert Concurrency.limits_for(account, :linux) == %{vcpus: 48, memory_gb: 80}
    assert Concurrency.limits_for(account, :macos) == %{vcpus: 18, memory_gb: 42}
  end
end
