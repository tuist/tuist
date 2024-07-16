defmodule Tuist.BillingFixtures do
  @moduledoc false

  alias Tuist.Repo
  alias Tuist.Billing.Subscription
  alias Tuist.TestUtilities

  def subscription_fixture(opts \\ []) do
    plan = opts |> Keyword.get(:plan, :pro)
    subscription_id = opts |> Keyword.get(:subscription_id, "#{TestUtilities.unique_integer()}")
    status = opts |> Keyword.get(:status, "active")

    default_payment_method =
      opts |> Keyword.get(:default_payment_method, "#{TestUtilities.unique_integer()}")

    account_id =
      Keyword.get_lazy(opts, :account_id, fn ->
        organization_id = Tuist.AccountsFixtures.organization_fixture().id

        Repo.get_by!(Tuist.Accounts.Account,
          organization_id: organization_id
        ).id
      end)

    Subscription.create_changeset(%Subscription{}, %{
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
