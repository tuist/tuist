defmodule TuistCloud.BillingTest do
  alias TuistCloud.BillingFixtures
  alias TuistCloud.Billing.PaymentMethod
  alias TuistCloud.Billing.Card
  alias TuistCloud.Billing.Customer
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
          flat_monthly: ["air.flat.monthly"]
        },
        pro: %{
          usage: ["pro.usage"],
          flat_monthly: ["pro.flat.monthly"],
          flat_yearly: ["pro.flat.yearly"]
        },
        enterprise: %{
          flat_monthly: ["enterprise.flat.monthly"],
          flat_yearly: ["enterprise.flat.yearly"]
        }
      }
    end)

    Stripe.Customer
    |> stub(:create, fn _ -> {:ok, %Stripe.Customer{id: "customer_id"}} end)

    :ok
  end

  describe "on_subscription_change/1" do
    test "when it's a new trial air subscription" do
      # Given
      user = AccountsFixtures.user_fixture(customer_id: "customer_id")
      account = Accounts.get_account_from_user(user)

      # When
      Billing.on_subscription_change(%{
        id: "sub_some-id",
        status: "trialing",
        customer: "customer_id",
        default_payment_method: nil,
        items: %{data: [%{price: %{id: "air.usage"}}, %{price: %{id: "air.flat.monthly"}}]},
        trial_end: 1_722_433_329
      })

      # Then
      subscription = Billing.get_current_active_subscription(account)
      assert subscription.plan == :air
      assert subscription.status == "trialing"
      assert subscription.trial_end == ~U[2024-07-31 13:42:09Z]
    end

    test "when it's a new air subscription" do
      # Given
      user = AccountsFixtures.user_fixture(customer_id: "customer_id")
      account = Accounts.get_account_from_user(user)

      # When
      Billing.on_subscription_change(%{
        id: "sub_some-id",
        status: "active",
        customer: "customer_id",
        default_payment_method: "pm_some-id",
        items: %{data: [%{price: %{id: "air.usage"}}, %{price: %{id: "air.flat.monthly"}}]}
      })

      # Then
      subscription = Billing.get_current_active_subscription(account)
      assert subscription.plan == :air
      assert subscription.default_payment_method == "pm_some-id"
    end

    test "when a user downgrades from the pro to the air plan" do
      # Given
      user = AccountsFixtures.user_fixture(customer_id: "customer_id")
      account = Accounts.get_account_from_user(user)

      Billing.on_subscription_change(%{
        id: "sub_some-id",
        status: "active",
        customer: "customer_id",
        default_payment_method: nil,
        items: %{data: [%{price: %{id: "pro.usage"}}, %{price: %{id: "pro.flat.monthly"}}]}
      })

      # When
      Billing.on_subscription_change(%{
        id: "sub_some-id",
        status: "active",
        customer: "customer_id",
        default_payment_method: "pm_some-id",
        items: %{data: [%{price: %{id: "air.usage"}}, %{price: %{id: "air.flat.monthly"}}]}
      })

      # Then
      assert Billing.get_current_active_subscription(account).plan == :air
    end

    test "when a default_payment_method is updated" do
      # Given
      user = AccountsFixtures.user_fixture(customer_id: "customer_id")
      account = Accounts.get_account_from_user(user)

      Billing.on_subscription_change(%{
        id: "sub_some-id",
        status: "active",
        customer: "customer_id",
        default_payment_method: nil,
        items: %{data: [%{price: %{id: "pro.usage"}}, %{price: %{id: "pro.flat.monthly"}}]}
      })

      # When
      Billing.on_subscription_change(%{
        id: "sub_some-id",
        status: "active",
        customer: "customer_id",
        default_payment_method: "pm_some-different-id",
        items: %{data: [%{price: %{id: "pro.usage"}}, %{price: %{id: "pro.flat.monthly"}}]}
      })

      # Then
      assert Billing.get_current_active_subscription(account).default_payment_method ==
               "pm_some-different-id"
    end

    test "when it's a new monthly pro subscription" do
      # Given
      user = AccountsFixtures.user_fixture(customer_id: "customer_id")
      account = Accounts.get_account_from_user(user)

      # When
      Billing.on_subscription_change(%{
        id: "sub_some-id",
        status: "active",
        customer: "customer_id",
        default_payment_method: "pm_some-id",
        items: %{data: [%{price: %{id: "pro.usage"}}, %{price: %{id: "pro.flat.monthly"}}]}
      })

      # Then
      assert Billing.get_current_active_subscription(account).plan == :pro
    end

    test "when it's a new enterprise monthly subscription" do
      # Given
      user = AccountsFixtures.user_fixture(customer_id: "customer_id")
      account = Accounts.get_account_from_user(user)

      # When
      Billing.on_subscription_change(%{
        id: "sub_some-id",
        status: "active",
        customer: "customer_id",
        default_payment_method: nil,
        items: %{data: [%{price: %{id: "enterprise.flat.monthly"}}]}
      })

      # Then
      assert Billing.get_current_active_subscription(account).plan == :enterprise
    end

    test "when it's a new enterprise yearly subscription" do
      # Given
      user = AccountsFixtures.user_fixture(customer_id: "customer_id")
      account = Accounts.get_account_from_user(user)

      # When
      Billing.on_subscription_change(%{
        id: "sub_some-id",
        status: "active",
        customer: "customer_id",
        default_payment_method: nil,
        items: %{data: [%{price: %{id: "enterprise.flat.yearly"}}]}
      })

      # Then
      assert Billing.get_current_active_subscription(account).plan == :enterprise
    end

    test "when a user cancels a subscription" do
      # Given
      user = AccountsFixtures.user_fixture(customer_id: "customer_id")
      account = Accounts.get_account_from_user(user)

      Billing.on_subscription_change(%{
        id: "sub_some-id",
        status: "active",
        customer: "customer_id",
        default_payment_method: "pm_some-id",
        items: %{data: [%{price: %{id: "pro.usage"}}, %{price: %{id: "pro.flat.monthly"}}]}
      })

      Stripe.Subscription
      |> stub(:cancel, fn "sub_some-id" -> {:ok, %Stripe.Subscription{status: "canceled"}} end)

      # When
      Billing.on_subscription_change(%{
        id: "sub_some-id",
        status: "canceled",
        customer: "customer_id",
        default_payment_method: "pm_some-id",
        items: %{data: [%{price: %{id: "pro.usage"}}, %{price: %{id: "pro.flat.monthly"}}]}
      })

      # Then
      assert Billing.get_current_active_subscription(account) == nil
    end
  end

  describe "start_trial/1" do
    test "starts a new air trial" do
      # Given
      user = AccountsFixtures.user_fixture(customer_id: "customer_id")
      account = Accounts.get_account_from_user(user)
      customer_id = account.customer_id

      Stripe.Subscription
      |> expect(:create, fn %{
                              customer: ^customer_id,
                              items: [
                                %{price: "air.usage"},
                                %{price: "air.flat.monthly", quantity: 1}
                              ],
                              trial_period_days: 30
                            } ->
        {:ok, %{}}
      end)

      # When
      Billing.start_trial(%{account: account, plan: :air})
    end
  end

  describe "update_plan/1" do
    test "creates a new session when upgrading to the pro plan if there is no current active subscription" do
      # Given
      user = AccountsFixtures.user_fixture(customer_id: "customer_id")
      account = Accounts.get_account_from_user(user)
      customer_id = account.customer_id

      Stripe.Checkout.Session
      |> stub(:create, fn %{
                            success_url: "success_url",
                            line_items: [
                              %{price: "pro.usage"},
                              %{price: "pro.flat.monthly", quantity: 1}
                            ],
                            mode: "subscription",
                            customer: ^customer_id
                          } ->
        {:ok, %{url: "session_url"}}
      end)

      # When
      session_url =
        Billing.update_plan(%{plan: :pro, account: account, success_url: "success_url"})

      # Then
      assert session_url == "session_url"
    end

    test "updates a subscription to the pro plan if the current active plan is air" do
      # Given
      user = AccountsFixtures.user_fixture(customer_id: "customer_id")
      account = Accounts.get_account_from_user(user)

      Stripe.Subscription
      |> stub(:update, fn "sub_some-id",
                          %{
                            items: [
                              %{id: "air.usage", deleted: true},
                              %{id: "air.flat.monthly", deleted: true},
                              %{price: "pro.usage"},
                              %{price: "pro.flat.monthly", quantity: 1}
                            ]
                          } ->
        {:ok, %{}}
      end)

      Stripe.Subscription
      |> stub(:retrieve, fn "sub_some-id" ->
        {:ok,
         %Stripe.Subscription{items: %{data: [%{id: "air.usage"}, %{id: "air.flat.monthly"}]}}}
      end)

      Billing.on_subscription_change(%{
        id: "sub_some-id",
        status: "active",
        customer: "customer_id",
        default_payment_method: "pm_some-id",
        items: %{data: [%{price: %{id: "air.usage"}}, %{price: %{id: "air.flat.monthly"}}]}
      })

      # When
      session_url =
        Billing.update_plan(%{plan: :pro, account: account, success_url: "success_url"})

      # Then
      assert session_url == nil
    end

    test "updates a subscription to the air plan if the current active plan is pro" do
      # Given
      user = AccountsFixtures.user_fixture(customer_id: "customer_id")
      account = Accounts.get_account_from_user(user)

      Stripe.Subscription
      |> stub(:update, fn "sub_some-id",
                          %{
                            items: [
                              %{id: "pro.usage", deleted: true},
                              %{id: "pro.flat.monthly", deleted: true},
                              %{price: "air.usage"},
                              %{price: "air.flat.monthly", quantity: 1}
                            ]
                          } ->
        {:ok, %{}}
      end)

      Stripe.Subscription
      |> stub(:retrieve, fn "sub_some-id" ->
        {:ok,
         %Stripe.Subscription{items: %{data: [%{id: "pro.usage"}, %{id: "pro.flat.monthly"}]}}}
      end)

      Billing.on_subscription_change(%{
        id: "sub_some-id",
        status: "active",
        customer: "customer_id",
        default_payment_method: "pm_some-id",
        items: %{data: [%{price: %{id: "pro.usage"}}, %{price: %{id: "pro.flat.monthly"}}]}
      })

      # When
      session_url =
        Billing.update_plan(%{plan: :air, account: account, success_url: "success_url"})

      # Then
      assert session_url == nil
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

  describe "get_customer_by_id/1" do
    test "returns the customer when it exists" do
      # Given
      customer_id = "customer_id"
      email = "customer_email"

      Stripe.Customer
      |> stub(:retrieve, fn ^customer_id ->
        {:ok, %Stripe.Customer{id: customer_id, email: email}}
      end)

      # When
      customer = Billing.get_customer_by_id(customer_id)

      # Then
      assert customer == %Customer{
               id: customer_id,
               email: email
             }
    end
  end

  describe "get_payment_method_by_id/1" do
    test "returns the payment method when it exists" do
      # Given
      payment_method_id = "payment_method_id"

      card = %Stripe.Card{
        brand: "visa",
        last4: "4242",
        exp_month: 12,
        exp_year: 2022
      }

      Stripe.PaymentMethod
      |> stub(:retrieve, fn ^payment_method_id ->
        {:ok, %Stripe.PaymentMethod{id: payment_method_id, card: card}}
      end)

      # When
      payment_method = Billing.get_payment_method_by_id(payment_method_id)

      # Then
      assert payment_method == %PaymentMethod{
               id: payment_method_id,
               card: %Card{
                 brand: "visa",
                 last4: "4242",
                 exp_month: 12,
                 exp_year: 2022
               }
             }
    end
  end

  describe "get_current_active_subscription/1" do
    test "gets the current active subscription" do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      subscription = BillingFixtures.subscription_fixture(account_id: account.id)

      # When
      got = Billing.get_current_active_subscription(account)

      # Then
      assert got == subscription
    end

    test "returns the most recent active subscription when there are multiple subscriptions cancelled and one active" do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      subscription = BillingFixtures.subscription_fixture(account_id: account.id)
      BillingFixtures.subscription_fixture(account_id: account.id, status: "canceled")
      BillingFixtures.subscription_fixture(status: "canceled")

      # When
      got = Billing.get_current_active_subscription(account)

      # Then
      assert got == subscription
    end

    test "gets the latest active subscription if there are mutliple active subscriptions" do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)

      BillingFixtures.subscription_fixture(
        account_id: account.id,
        inserted_at: ~N[2021-01-01 00:00:00]
      )

      subscription =
        BillingFixtures.subscription_fixture(
          account_id: account.id,
          inserted_at: ~N[2021-01-01 01:00:00]
        )

      # When
      got = Billing.get_current_active_subscription(account)

      # Then
      assert got == subscription
    end

    test "returns nil if only a canceled subscription exists for a given account" do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      BillingFixtures.subscription_fixture(account_id: account.id, status: "canceled")

      # When
      got = Billing.get_current_active_subscription(account)

      # Then
      assert got == nil
    end
  end
end
