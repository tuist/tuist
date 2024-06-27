defmodule TuistCloud.Billing do
  @moduledoc """
  A module for operations related to billing.
  """

  alias TuistCloud.Billing.Card
  alias TuistCloud.Billing.Customer
  alias TuistCloud.Billing.PaymentMethod
  alias TuistCloud.Billing.Subscription
  alias TuistCloud.Environment
  alias TuistCloud.Accounts
  alias TuistCloud.Accounts.Account
  alias TuistCloud.Repo

  import Ecto.Query, only: [from: 2]

  def create_customer(%{name: name, email: email}) do
    if enabled?() do
      {:ok, customer} = Stripe.Customer.create(%{name: name, email: email})
      customer.id
    else
      nil
    end
  end

  def create_session(customer) do
    {:ok, session} = Stripe.BillingPortal.Session.create(%{customer: customer})
    session
  end

  def update_remote_cache_hit_meter({customer_id, count}) do
    path = Stripe.OpenApi.Path.replace_path_params("/v1/billing/meter_events", [], [])

    identifier =
      "#{customer_id}-#{TuistCloud.Time.utc_now() |> Timex.format!("{YYYY}.{0M}.{D}")}"

    {:ok, _} =
      Stripe.Request.new_request([])
      |> Stripe.Request.put_endpoint(path)
      |> Stripe.Request.put_params(%{
        event_name: "remote_cache_hit",
        identifier: identifier,
        payload: %{
          value: count,
          stripe_customer_id: customer_id
        }
      })
      |> Stripe.Request.put_method(:post)
      |> Stripe.Request.make_request()
  end

  def update_plan(%{
        plan: plan,
        account: %Account{} = account,
        success_url: success_url
      }) do
    customer_id = account.customer_id
    available_prices = TuistCloud.Environment.stripe_prices()

    usage_prices =
      available_prices[plan][:usage]
      |> Enum.map(&%{price: &1})

    flat_prices =
      available_prices[plan][:flat_monthly]
      |> Enum.map(&%{price: &1, quantity: 1})
      |> Enum.take(1)

    current_subscription = get_current_active_subscription(account)

    if is_nil(current_subscription) do
      {:ok, session} =
        Stripe.Checkout.Session.create(%{
          success_url: success_url,
          line_items: usage_prices ++ flat_prices,
          mode: "subscription",
          customer: customer_id
        })

      session.url
    else
      {:ok, stripe_subscription} =
        Stripe.Subscription.retrieve(current_subscription.subscription_id)

      item_to_delete = stripe_subscription.items.data |> Enum.map(&%{id: &1.id, deleted: true})

      {:ok, _} =
        Stripe.Subscription.update(current_subscription.subscription_id, %{
          items: item_to_delete ++ usage_prices ++ flat_prices
        })

      nil
    end
  end

  def on_subscription_change(subscription) do
    account = Accounts.get_account_from_customer_id(subscription.customer)
    active = subscription.status in ["active", "trialing"]
    subscription_prices = subscription.items.data |> Enum.map(& &1.price.id)
    available_prices = TuistCloud.Environment.stripe_prices()

    plan =
      if active do
        plan =
          available_prices
          |> Enum.filter(fn {_, plan_prices} ->
            usage = plan_prices[:usage]
            flat = plan_prices[:flat_monthly]

            # The subscription must:
            #   - Include all the usage-based prices
            #   - Include at least one flat-based price (monthly or yearly)
            Enum.all?(usage, &Enum.member?(subscription_prices, &1)) and
              Enum.any?(flat, &Enum.member?(subscription_prices, &1))
          end)
          |> Enum.map(&elem(&1, 0))
          |> List.first()

        if plan == nil, do: :none, else: plan
      else
        :none
      end

    current_subscription = Repo.get_by(Subscription, subscription_id: subscription.id)

    cond do
      is_nil(current_subscription) ->
        Subscription.create_changeset(%Subscription{}, %{
          plan: plan,
          subscription_id: subscription.id,
          status: subscription.status,
          account_id: account.id,
          default_payment_method: subscription.default_payment_method
        })
        |> Repo.insert!()

      active ->
        Subscription.update_changeset(current_subscription, %{
          plan: plan,
          status: subscription.status,
          default_payment_method: subscription.default_payment_method
        })
        |> Repo.update!()

      not active ->
        Subscription.update_changeset(current_subscription, %{
          status: subscription.status,
          default_payment_method: subscription.default_payment_method
        })
        |> Repo.update!()
    end

    :ok
  end

  def get_customer_by_id(customer_id) do
    {:ok, customer} = Stripe.Customer.retrieve(customer_id)

    %Customer{
      id: customer.id,
      email: customer.email
    }
  end

  def get_payment_method_by_id(payment_method_id) do
    {:ok, payment_method} = Stripe.PaymentMethod.retrieve(payment_method_id)

    %PaymentMethod{
      id: payment_method.id,
      card: %Card{
        brand: payment_method.card.brand,
        last4: payment_method.card.last4,
        exp_month: payment_method.card.exp_month,
        exp_year: payment_method.card.exp_year
      }
    }
  end

  @doc """
  Given an account, it returns the latest subscription that is active or trialing.
  """
  def get_current_active_subscription(%Account{} = account) do
    from(s in Subscription,
      where: s.account_id == ^account.id,
      where: s.status == "active" or s.status == "trialing",
      order_by: [desc: s.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  def enabled? do
    Environment.stripe_configured?()
  end
end
