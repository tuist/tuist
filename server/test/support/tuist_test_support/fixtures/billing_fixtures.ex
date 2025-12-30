defmodule TuistTestSupport.Fixtures.BillingFixtures do
  @moduledoc false

  alias Tuist.Billing.Subscription
  alias Tuist.Repo

  def subscription_fixture(opts \\ []) do
    plan = Keyword.get(opts, :plan, :pro)

    subscription_id = Keyword.get(opts, :subscription_id, "#{TuistTestSupport.Utilities.unique_integer()}")

    status = Keyword.get(opts, :status, "active")

    default_payment_method = Keyword.get(opts, :default_payment_method, "#{TuistTestSupport.Utilities.unique_integer()}")

    account_id =
      Keyword.get_lazy(opts, :account_id, fn ->
        organization_id = TuistTestSupport.Fixtures.AccountsFixtures.organization_fixture().id

        Repo.get_by!(Tuist.Accounts.Account,
          organization_id: organization_id
        ).id
      end)

    %Subscription{}
    |> Subscription.create_changeset(%{
      plan: plan,
      subscription_id: subscription_id,
      status: status,
      account_id: account_id,
      default_payment_method: default_payment_method,
      inserted_at: Keyword.get(opts, :inserted_at, Tuist.Time.utc_now())
    })
    |> Repo.insert!()
  end
end
