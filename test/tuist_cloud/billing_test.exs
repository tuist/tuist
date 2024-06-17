defmodule TuistCloud.BillingTest do
  alias TuistCloud.Environment
  alias TuistCloud.Accounts
  alias TuistCloud.Accounts.Account
  alias TuistCloud.Billing
  alias TuistCloud.AccountsFixtures
  use TuistCloud.DataCase
  use Mimic

  setup do
    Environment
    |> stub(:stripe_configured?, fn -> true end)

    Environment
    |> stub(:stripe_prices, fn ->
      %{
        air: %{
          usage: ["air.usage"],
          flat: ["air.flat"]
        },
        pro: %{
          usage: ["air.usage.binary-cache", "air.usage.selective-testing"],
          flat: ["air.flat.monthly", "air.flat.yearly"]
        }
      }
    end)

    Stripe.Customer
    |> stub(:create, fn _ -> {:ok, %Stripe.Customer{id: "customer_id"}} end)

    :ok
  end

  describe "on_subscription_change/1" do
    test "when it's an air subscription" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      # When
      Billing.on_subscription_change(%{
        status: "active",
        customer: "customer_id",
        items: %{data: [%{price: %{id: "air.usage"}}, %{price: %{id: "air.flat"}}]}
      })

      # Then
      assert Accounts.get_account_by_id(account.id).plan == :air
    end

    test "when it's a monthly pro subscription" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      # When
      Billing.on_subscription_change(%{
        status: "active",
        customer: "customer_id",
        items: %{
          data: [
            %{price: %{id: "air.flat.monthly"}},
            %{price: %{id: "air.usage.binary-cache"}},
            %{price: %{id: "air.usage.selective-testing"}}
          ]
        }
      })

      # Then
      assert Accounts.get_account_by_id(account.id).plan == :pro
    end

    test "when it's a yearly pro subscription" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      # When
      Billing.on_subscription_change(%{
        status: "active",
        customer: "customer_id",
        items: %{
          data: [
            %{price: %{id: "air.flat.yearly"}},
            %{price: %{id: "air.usage.binary-cache"}},
            %{price: %{id: "air.usage.selective-testing"}}
          ]
        }
      })

      # Then
      assert Accounts.get_account_by_id(account.id).plan == :pro
    end
  end

  describe "update_remote_cache_hit_meter/1" do
    test "sends the right API request to Stripe" do
      # Given
      user = AccountsFixtures.user_fixture(preloads: [:account])
      customer_id = "customer_id"

      account =
        user.account |> Account.update_changeset(%{customer_id: customer_id}) |> Repo.update!()

      Stripe.Request
      |> stub(:make_request, fn %{
                                  method: :post,
                                  endpoint: "/v1/billing/meter_events",
                                  params: %{
                                    payload: %{value: 10, stripe_customer_id: ^customer_id},
                                    event_name: "remote_cache_hit"
                                  }
                                } ->
        {:ok, %{}}
      end)

      # When
      Billing.update_remote_cache_hit_meter({account.customer_id, 10})
    end
  end
end
