defmodule Tuist.Billing.Workers.ApplyStandingRunnerPrepaidWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Billing.Workers.ApplyStandingRunnerPrepaidWorker
  alias Tuist.Repo
  alias Tuist.Runners.Prepaid
  alias TuistTestSupport.Fixtures.AccountsFixtures

  defp job(account_id, period_start \\ "2026-10-21T01:29:59Z") do
    %Oban.Job{id: 1, args: %{"account_id" => account_id, "period_start" => period_start}}
  end

  defp account_fixture(attrs \\ %{}) do
    user = AccountsFixtures.user_fixture()

    user
    |> Accounts.get_account_from_user()
    |> Account.runner_prepaid_changeset(Map.take(attrs, [:runner_prepaid_monthly_minutes]))
    |> Repo.update!()
  end

  test "grants the account the standing level it carries" do
    account = account_fixture(%{runner_prepaid_monthly_minutes: 6_000})

    expect(Prepaid, :apply_standing_minutes, fn granted ->
      assert granted.id == account.id
      assert granted.runner_prepaid_monthly_minutes == 6_000
      {:ok, %{id: "ii_1"}}
    end)

    assert :ok = ApplyStandingRunnerPrepaidWorker.perform(job(account.id))
  end

  test "treats an account carrying no standing level as done" do
    account = account_fixture()

    stub(Prepaid, :apply_standing_minutes, fn _account -> {:ok, :no_standing_order} end)

    assert :ok = ApplyStandingRunnerPrepaidWorker.perform(job(account.id))
  end

  test "does not bill a trial account for credit it can never draw against" do
    # A trial carries no runner item, so its usage is not invoiced and a
    # grant has nothing to apply to. Charging for one would take money
    # for minutes that cannot be spent.
    account =
      %{runner_prepaid_monthly_minutes: 6_000}
      |> account_fixture()
      |> Account.runner_trial_changeset(%{runner_trial_started_at: DateTime.utc_now()})
      |> Repo.update!()

    assert account.runner_prepaid_monthly_minutes == 6_000

    reject(&Prepaid.apply_standing_minutes/1)

    assert :ok = ApplyStandingRunnerPrepaidWorker.perform(job(account.id))
  end

  test "treats an account that no longer exists as done" do
    reject(&Prepaid.apply_standing_minutes/1)

    assert :ok = ApplyStandingRunnerPrepaidWorker.perform(job(-1))
  end

  test "retries when the grant fails, since the minutes are still owed" do
    account = account_fixture(%{runner_prepaid_monthly_minutes: 6_000})

    stub(Prepaid, :apply_standing_minutes, fn _account -> {:error, :no_runner_prices_configured} end)

    assert {:error, :no_runner_prices_configured} = ApplyStandingRunnerPrepaidWorker.perform(job(account.id))
  end
end
