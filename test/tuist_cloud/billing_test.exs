defmodule TuistCloud.BillingTest do
  alias TuistCloud.Environment
  alias TuistCloud.Accounts
  alias TuistCloud.Billing
  alias TuistCloud.AccountsFixtures
  use TuistCloud.DataCase
  use Mimic

  test "sets plan to :enterprise if subscription is active" do
    # Given
    Environment
    |> stub(:stripe_configured?, fn -> true end)

    Stripe.Customer
    |> stub(:create, fn _ -> {:ok, %Stripe.Customer{id: "customer_id"}} end)

    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)

    # When
    Billing.update_plan(%{status: "active", customer: "customer_id"})

    # Then
    assert account.plan == :none
    assert Accounts.get_account_by_id(account.id).plan == :enterprise
  end

  test "sets plan to :enterprise if subscription is trialing" do
    # Given
    Environment
    |> stub(:stripe_configured?, fn -> true end)

    Stripe.Customer
    |> stub(:create, fn _ -> {:ok, %Stripe.Customer{id: "customer_id"}} end)

    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)

    # When
    Billing.update_plan(%{status: "trialing", customer: "customer_id"})

    # Then
    assert account.plan == :none
    assert Accounts.get_account_by_id(account.id).plan == :enterprise
  end

  test "sets plan to nil if subscription is not active" do
    # Given
    Environment
    |> stub(:stripe_configured?, fn -> true end)

    Stripe.Customer
    |> stub(
      :create,
      fn _ -> {:ok, %Stripe.Customer{id: "customer_id"}} end
    )

    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)
    account = Accounts.update_plan(account, :enterprise)

    # When
    Billing.update_plan(%{status: "canceled", customer: "customer_id"})

    # Then
    assert account.plan == :enterprise
    assert Accounts.get_account_by_id(account.id).plan == :none
  end
end
