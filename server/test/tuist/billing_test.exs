defmodule Tuist.BillingTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.Billing.Card
  alias Tuist.Billing.Customer
  alias Tuist.Billing.PaymentMethod
  alias Tuist.Environment
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup do
    stub(Environment, :stripe_prices, fn ->
      %{
        "air" => %{
          "usage" => ["air.usage"],
          "flat_monthly" => ["air.flat.monthly"]
        },
        "pro" => %{
          "usage" => ["pro.usage"],
          "flat_monthly" => ["pro.flat.monthly"],
          "flat_yearly" => ["pro.flat.yearly"]
        },
        "enterprise" => %{
          "flat_monthly" => ["enterprise.flat.monthly"],
          "flat_yearly" => ["enterprise.flat.yearly"]
        }
      }
    end)

    stub(Stripe.Customer, :create, fn _ -> {:ok, %Stripe.Customer{id: "customer_id"}} end)
    :ok
  end

  describe "create_customer" do
    test "creates the customer if it doesn't exist" do
      # Given
      email = "#{UUIDv7.generate()}@tuist.dev"
      name = UUIDv7.generate()
      customer_id = UUIDv7.generate()
      search_params = %{query: "email:\"#{email}\""}
      create_params = %{name: name, email: email}
      stub(Stripe.Customer, :search, fn ^search_params -> {:ok, %{data: []}} end)
      stub(Stripe.Customer, :create, fn ^create_params -> {:ok, %{id: customer_id}} end)

      # When/then
      assert Billing.create_customer(%{name: name, email: email}) == customer_id
    end
  end

  describe "get_payment_method_id_from_subscription_id/1" do
    test "returns the default payment method from the subscription if it exists" do
      # Given
      subscription_id = "subscription_id"
      payment_method_id = "payment_method_id"

      stub(Stripe.Subscription, :retrieve, fn ^subscription_id ->
        {:ok, %{default_payment_method: payment_method_id}}
      end)

      # When
      got = Billing.get_payment_method_id_from_subscription_id(subscription_id)

      # Then
      assert got == payment_method_id
    end

    test "returns the customer's invoice settings default payment method when the subscription has no default payment method" do
      # Given
      subscription_id = "subscription_id"
      payment_method_id = "payment_method_id"
      customer_id = "customer_id"

      stub(Stripe.Subscription, :retrieve, fn ^subscription_id ->
        {:ok, %{default_payment_method: nil, customer: customer_id}}
      end)

      stub(Stripe.Customer, :retrieve, fn ^customer_id ->
        {:ok, %{invoice_settings: %{default_payment_method: payment_method_id}}}
      end)

      # When
      got = Billing.get_payment_method_id_from_subscription_id(subscription_id)

      # Then
      assert got == payment_method_id
    end

    test "returns nil when the payment method id can't be obtained from neither the subscription nor the customer invoice settings" do
      # Given
      subscription_id = "subscription_id"
      customer_id = "customer_id"

      stub(Stripe.Subscription, :retrieve, fn ^subscription_id ->
        {:ok, %{default_payment_method: nil, customer: customer_id}}
      end)

      stub(Stripe.Customer, :retrieve, fn ^customer_id ->
        {:ok, %{invoice_settings: %{default_payment_method: nil}}}
      end)

      # When
      got = Billing.get_payment_method_id_from_subscription_id(subscription_id)

      # Then
      assert got == nil
    end
  end

  describe "get_estimated_next_payment/1" do
    test "when current_month_remote_cache_hits_count is under the threshold" do
      # Given
      remote_cache_hit_threshold = Billing.get_payment_thresholds()[:remote_cache_hits]
      current_month_remote_cache_hits_count = round(remote_cache_hit_threshold / 2)

      # When
      got =
        Billing.get_estimated_next_payment(%{
          current_month_remote_cache_hits_count: current_month_remote_cache_hits_count
        })

      # Then
      assert got == "$0.00"
    end

    test "when current_month_remote_cache_hits_count is above the threshold" do
      # Given
      remote_cache_hit_threshold = Billing.get_payment_thresholds()[:remote_cache_hits]
      current_month_remote_cache_hits_count = round(remote_cache_hit_threshold * 2)

      # When
      got =
        Billing.get_estimated_next_payment(%{
          current_month_remote_cache_hits_count: current_month_remote_cache_hits_count
        })

      # Then
      assert got ==
               50
               |> Money.new(:USD)
               |> Money.multiply(current_month_remote_cache_hits_count - remote_cache_hit_threshold)
               |> Money.to_string()
    end
  end

  describe "on_subscription_change/1" do
    test "when an account for the given customer doesn't exist" do
      # When
      assert(
        Billing.on_subscription_change(%{
          id: "sub_some-id",
          status: "trialing",
          customer: "non_existing_customer_id",
          default_payment_method: nil,
          items: %{data: [%{price: %{id: "air.usage"}}, %{price: %{id: "air.flat.monthly"}}]},
          trial_end: 1_722_433_329
        }) == :ok
      )
    end

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

      stub(Stripe.Subscription, :cancel, fn "sub_some-id" ->
        {:ok, %Stripe.Subscription{status: "canceled"}}
      end)

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

  describe "update_plan/1" do
    test "creates a new session when upgrading to the pro plan if there is no current active subscription" do
      # Given
      user = AccountsFixtures.user_fixture(customer_id: "customer_id")
      account = Accounts.get_account_from_user(user)
      customer_id = account.customer_id

      stub(Stripe.Checkout.Session, :create, fn %{
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
      assert session_url == {:ok, {:external_redirect, "session_url"}}
    end

    test "updates a subscription to the pro plan if the current active plan is air" do
      # Given
      user = AccountsFixtures.user_fixture(customer_id: "customer_id")
      account = Accounts.get_account_from_user(user)

      stub(Stripe.Subscription, :update, fn "sub_some-id",
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

      stub(Stripe.Subscription, :retrieve, fn "sub_some-id" ->
        {:ok, %Stripe.Subscription{items: %{data: [%{id: "air.usage"}, %{id: "air.flat.monthly"}]}}}
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
      assert session_url == :ok
    end

    test "updates a subscription to the air plan if the current active plan is pro" do
      # Given
      user = AccountsFixtures.user_fixture(customer_id: "customer_id")
      account = Accounts.get_account_from_user(user)

      stub(Stripe.Subscription, :update, fn "sub_some-id",
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

      stub(Stripe.Subscription, :retrieve, fn "sub_some-id" ->
        {:ok, %Stripe.Subscription{items: %{data: [%{id: "pro.usage"}, %{id: "pro.flat.monthly"}]}}}
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
      assert session_url == :ok
    end
  end

  describe "update_remote_cache_hit_meter/2" do
    test "sends the right API request to Stripe" do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account])
      customer_id = "customer_id"

      account =
        user.account |> Account.billing_changeset(%{customer_id: customer_id}) |> Repo.update!()

      stub(Stripe.Request, :make_request, fn %{
                                               method: :post,
                                               endpoint: "/v1/billing/meter_events",
                                               params: %{
                                                 payload: %{
                                                   value: 10,
                                                   stripe_customer_id: ^customer_id
                                                 },
                                                 event_name: "remote_cache_hit"
                                               }
                                             } ->
        {:ok, %{}}
      end)

      stub(Tuist.CommandEvents, :get_yesterdays_remote_cache_hits_count_for_customer, fn ^customer_id -> 10 end)

      # When
      Billing.update_remote_cache_hit_meter(account.customer_id, "job-1")
    end
  end

  describe "update_namespace_usage_meter/2" do
    test "sends correct Stripe meter event with instance unit minutes" do
      customer_id = "cus_123"
      idempotency_key = "job-xyz"

      account = %Account{customer_id: customer_id, namespace_tenant_id: "tenant-abc"}

      stub(Accounts, :get_account_from_customer_id, fn ^customer_id -> {:ok, account} end)

      stub(Tuist.Namespace, :get_tenant_usage, fn ^account, _start_date, _end_date ->
        {:ok, %{"total" => %{"instanceMinutes" => %{"unit" => 137}}}}
      end)

      expect(Date, :utc_today, fn -> ~D[2024-11-21] end)
      expect(Tuist.Time, :utc_now, fn -> ~U[2024-11-21 00:00:00Z] end)

      expect(Stripe.Request, :make_request, fn req ->
        assert %{
                 method: :post,
                 endpoint: "/v1/billing/meter_events",
                 params: %{
                   event_name: "namespace_unit_minute",
                   payload: %{
                     value: 137,
                     stripe_customer_id: ^customer_id
                   }
                 }
               } = req

        assert req.headers["Idempotency-Key"] == "#{idempotency_key}-namespace"

        {:ok, %{}}
      end)

      assert {:ok, :updated} = Billing.update_namespace_usage_meter(customer_id, idempotency_key)
    end

    test "does nothing when account has no namespace tenant id" do
      customer_id = "cus_no_ns"
      idempotency_key = "job-noop"

      account = %Account{customer_id: customer_id, namespace_tenant_id: nil}

      stub(Accounts, :get_account_from_customer_id, fn ^customer_id -> {:ok, account} end)

      reject(&Stripe.Request.make_request/1)

      assert {:ok, %Account{customer_id: ^customer_id}} =
               Billing.update_namespace_usage_meter(customer_id, idempotency_key)
    end
  end

  describe "get_customer_by_id/1" do
    test "returns the customer when it exists" do
      # Given
      customer_id = "customer_id"
      email = "customer_email"

      stub(Stripe.Customer, :retrieve, fn ^customer_id ->
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

      stub(Stripe.PaymentMethod, :retrieve, fn ^payment_method_id ->
        {:ok,
         %Stripe.PaymentMethod{
           id: payment_method_id,
           billing_details: %{
             name: "Carl"
           },
           card: card,
           type: "card"
         }}
      end)

      # When
      payment_method = Billing.get_payment_method_by_id(payment_method_id)

      # Then
      assert payment_method == %PaymentMethod{
               id: payment_method_id,
               type: "card",
               card: %Card{
                 cardholder_name: "Carl",
                 brand: "visa",
                 last4: "4242",
                 exp_month: 12,
                 exp_year: 2022
               }
             }
    end
  end

  describe "get_yesterdays_customer_llm_token_usage/1" do
    test "sums only yesterday's token usage for the given customer" do
      # Given
      today = ~U[2025-01-02 12:00:00Z]
      stub(DateTime, :utc_now, fn -> today end)

      org = AccountsFixtures.organization_fixture()
      account = Tuist.Repo.get_by!(Account, organization_id: org.id)
      account = Tuist.Repo.update!(Account.billing_changeset(account, %{customer_id: "cust_" <> UUIDv7.generate()}))

      other_org = AccountsFixtures.organization_fixture()
      other_account = Tuist.Repo.get_by!(Account, organization_id: other_org.id)

      other_account =
        Tuist.Repo.update!(Account.billing_changeset(other_account, %{customer_id: "cust_" <> UUIDv7.generate()}))

      # Yesterday usage for target account (should be included)
      {:ok, _} =
        Billing.create_token_usage(%{
          input_tokens: 100,
          output_tokens: 50,
          model: "gpt-4",
          feature: "qa",
          feature_resource_id: UUIDv7.generate(),
          account_id: account.id,
          timestamp: ~U[2025-01-01 08:00:00Z]
        })

      # Today usage (outside yesterday) for target account (excluded)
      {:ok, _} =
        Billing.create_token_usage(%{
          input_tokens: 200,
          output_tokens: 100,
          model: "gpt-4",
          feature: "qa",
          feature_resource_id: UUIDv7.generate(),
          account_id: account.id,
          timestamp: ~U[2025-01-02 09:00:00Z]
        })

      # Yesterday usage for another account (excluded by customer_id)
      {:ok, _} =
        Billing.create_token_usage(%{
          input_tokens: 300,
          output_tokens: 150,
          model: "gpt-4",
          feature: "qa",
          feature_resource_id: UUIDv7.generate(),
          account_id: other_account.id,
          timestamp: ~U[2025-01-01 10:00:00Z]
        })

      # When
      {input, output} = Billing.get_yesterdays_customer_llm_token_usage(account.customer_id)

      # Then
      assert {input, output} == {100, 50}
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
