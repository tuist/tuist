defmodule Tuist.Billing.Workers.ApplyStandingRunnerPrepaidWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.Billing.CreditGrants
  alias Tuist.Billing.Workers.ApplyStandingRunnerPrepaidWorker
  alias Tuist.Environment
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @period "2026-10-21T01:29:59Z"
  @older_period "2026-09-21T01:29:59Z"

  setup do
    stub(Environment, :stripe_prices, fn ->
      %{"runners" => %{"runner_macos_compute_unit_milliseconds" => "price_runner_macos"}}
    end)

    stub(Billing, :current_billing_period, fn _account ->
      {~U[2026-09-21 01:29:59Z], ~U[2026-10-21 01:29:59Z]}
    end)

    :ok
  end

  defp job(account_id, period_start \\ @period) do
    %Oban.Job{id: 1, args: %{"account_id" => account_id, "period_start" => period_start}}
  end

  defp account_fixture(attrs \\ %{}) do
    [customer_id: "cus_standing_#{System.unique_integer([:positive])}"]
    |> AccountsFixtures.user_fixture()
    |> Accounts.get_account_from_user()
    |> Account.runner_prepaid_changeset(Map.take(attrs, [:runner_prepaid_monthly_minutes]))
    |> Repo.update!()
  end

  # Stripe as far as prepaid needs it, including the one behaviour these
  # tests are about: a request carrying an idempotency key Stripe has
  # already seen returns the object it made the first time rather than a
  # new one, even when the first response never reached us.
  defp fake_stripe(opts \\ []) do
    {:ok, stripe} =
      Agent.start_link(fn ->
        %{
          items: %{},
          item_keys: %{},
          grants: [],
          grant_keys: %{},
          lose_next_charge_response: Keyword.get(opts, :lose_first_charge_response, false)
        }
      end)

    create_item = fn params, request_opts ->
      key = Keyword.get(request_opts, :idempotency_key)

      Agent.get_and_update(stripe, fn state ->
        case key && Map.get(state.item_keys, key) do
          nil -> new_charge(state, params, key)
          id -> {{:ok, %{id: id}}, state}
        end
      end)
    end

    stub(Stripe.Invoiceitem, :create, fn params -> create_item.(params, []) end)
    stub(Stripe.Invoiceitem, :create, fn params, request_opts -> create_item.(params, request_opts) end)

    stub(Stripe.Invoiceitem, :delete, fn id ->
      Agent.update(stripe, fn state -> put_in(state, [:items, id, :deleted], true) end)
      {:ok, %{id: id, deleted: true}}
    end)

    stub(CreditGrants, :create, fn attrs ->
      Agent.get_and_update(stripe, fn state ->
        case Map.get(state.grant_keys, attrs.idempotency_key) do
          nil ->
            grant = %{
              id: "credgr_#{length(state.grants) + 1}",
              voided_at: nil,
              expires_at: nil,
              amount: %{type: "monetary", monetary: %{currency: "usd", value: attrs.amount_cents}},
              metadata: attrs.metadata
            }

            {{:ok, grant},
             %{
               state
               | grants: state.grants ++ [grant],
                 grant_keys: Map.put(state.grant_keys, attrs.idempotency_key, grant.id)
             }}

          id ->
            {{:ok, Enum.find(state.grants, &(&1.id == id))}, state}
        end
      end)
    end)

    stub(CreditGrants, :list_for_customer, fn _customer_id -> {:ok, Agent.get(stripe, & &1.grants)} end)

    stub(CreditGrants, :void, fn id ->
      Agent.update(stripe, fn state ->
        %{state | grants: Enum.map(state.grants, &if(&1.id == id, do: %{&1 | voided_at: 1_760_000_000}, else: &1))}
      end)

      {:ok, %{id: id}}
    end)

    stub(CreditGrants, :available_balance_cents, fn _customer_id, _grant_id -> {:ok, 0} end)

    stripe
  end

  defp new_charge(state, params, key) do
    id = "ii_#{map_size(state.items) + 1}"
    state = %{state | items: Map.put(state.items, id, %{amount: params.amount, deleted: false})}
    state = if key, do: %{state | item_keys: Map.put(state.item_keys, key, id)}, else: state

    if state.lose_next_charge_response do
      {{:error, %Stripe.Error{source: :network, code: :network_error, message: "timeout"}},
       %{state | lose_next_charge_response: false}}
    else
      {{:ok, %{id: id}}, state}
    end
  end

  defp charges_created(stripe), do: Agent.get(stripe, &map_size(&1.items))
  defp live_grants(stripe), do: Agent.get(stripe, fn state -> Enum.count(state.grants, &is_nil(&1.voided_at)) end)

  test "grants the account the standing level it carries" do
    stripe = fake_stripe()
    account = account_fixture(%{runner_prepaid_monthly_minutes: 6_000})

    assert :ok = ApplyStandingRunnerPrepaidWorker.perform(job(account.id))

    assert charges_created(stripe) == 1
    assert live_grants(stripe) == 1
    assert Agent.get(stripe, &(&1.items |> Map.values() |> hd())).amount == 36_000
  end

  test "does not grant a period again once its first job has been pruned" do
    # Completed jobs are pruned within hours, so the uniqueness key stops
    # recognising a period. A stale event then rewrites the recorded period
    # backwards, the newer event advances it again, and the same period is
    # enqueued a second time. Re-granting would refill a balance the
    # customer is part-way through spending.
    stripe = fake_stripe()
    account = account_fixture(%{runner_prepaid_monthly_minutes: 6_000})

    assert :ok = ApplyStandingRunnerPrepaidWorker.perform(job(account.id))
    assert :ok = ApplyStandingRunnerPrepaidWorker.perform(job(account.id))

    assert charges_created(stripe) == 1
    assert live_grants(stripe) == 1
  end

  test "does not grant an older period after a newer one has been granted" do
    stripe = fake_stripe()
    account = account_fixture(%{runner_prepaid_monthly_minutes: 6_000})

    assert :ok = ApplyStandingRunnerPrepaidWorker.perform(job(account.id, @period))
    assert :ok = ApplyStandingRunnerPrepaidWorker.perform(job(account.id, @older_period))

    assert charges_created(stripe) == 1
  end

  test "does not bill twice when a charge's response is lost and the job retries" do
    # Stripe accepts the charge but the response never arrives, so the
    # attempt fails and Oban retries it. Without a stable key the retry
    # raises a second charge, and the first has no grant pointing at it for
    # a later set to withdraw.
    stripe = fake_stripe(lose_first_charge_response: true)
    account = account_fixture(%{runner_prepaid_monthly_minutes: 6_000})

    assert {:error, _reason} = ApplyStandingRunnerPrepaidWorker.perform(job(account.id))
    assert :ok = ApplyStandingRunnerPrepaidWorker.perform(job(account.id))

    assert charges_created(stripe) == 1
    assert live_grants(stripe) == 1
  end

  test "treats an account carrying no standing level as done" do
    fake_stripe()
    account = account_fixture()

    reject(&Stripe.Invoiceitem.create/1)
    reject(&Stripe.Invoiceitem.create/2)

    assert :ok = ApplyStandingRunnerPrepaidWorker.perform(job(account.id))
  end

  test "does not bill a trial account for credit it can never draw against" do
    # A trial carries no runner item, so its usage is not invoiced and a
    # grant has nothing to apply to.
    fake_stripe()

    account =
      %{runner_prepaid_monthly_minutes: 6_000}
      |> account_fixture()
      |> Account.runner_trial_changeset(%{runner_trial_started_at: DateTime.utc_now()})
      |> Repo.update!()

    reject(&Stripe.Invoiceitem.create/1)
    reject(&Stripe.Invoiceitem.create/2)

    assert :ok = ApplyStandingRunnerPrepaidWorker.perform(job(account.id))
  end

  test "treats an account that no longer exists as done" do
    fake_stripe()

    reject(&Stripe.Invoiceitem.create/1)
    reject(&Stripe.Invoiceitem.create/2)

    assert :ok = ApplyStandingRunnerPrepaidWorker.perform(job(-1))
  end

  test "retries when the grant fails, since the minutes are still owed" do
    fake_stripe()
    stub(Environment, :stripe_prices, fn -> %{"runners" => %{}} end)
    account = account_fixture(%{runner_prepaid_monthly_minutes: 6_000})

    assert {:error, :no_runner_prices_configured} = ApplyStandingRunnerPrepaidWorker.perform(job(account.id))
  end
end
