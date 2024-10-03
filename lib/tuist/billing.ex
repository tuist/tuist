defmodule Tuist.Billing do
  @moduledoc """
  A module for operations related to billing.
  """

  alias Tuist.Billing.Card
  alias Tuist.Billing.Customer
  alias Tuist.Billing.PaymentMethod
  alias Tuist.Billing.Subscription
  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Repo

  import Ecto.Query, only: [from: 2]

  def create_customer(%{name: name, email: email}) do
    {:ok, customer} = Stripe.Customer.create(%{name: name, email: email})
    customer.id
  end

  def create_session(customer) do
    {:ok, session} = Stripe.BillingPortal.Session.create(%{customer: customer})
    session
  end

  def update_remote_cache_hit_meter({customer_id, count}) do
    path = Stripe.OpenApi.Path.replace_path_params("/v1/billing/meter_events", [], [])

    identifier =
      "#{customer_id}-#{Tuist.Time.utc_now() |> Timex.format!("{YYYY}.{0M}.{D}")}"

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

  def start_trial(%{plan: plan, account: %Account{customer_id: customer_id}}) do
    subscription_items = get_subscription_items(plan)

    Stripe.Subscription.create(%{
      customer: customer_id,
      items: subscription_items,
      trial_period_days: 30
    })
  end

  def update_plan(%{
        plan: plan,
        account: %Account{} = account,
        success_url: success_url
      }) do
    customer_id = account.customer_id

    current_subscription = get_current_active_subscription(account)

    subscription_items = get_subscription_items(plan)

    if is_nil(current_subscription) do
      {:ok, session} =
        Stripe.Checkout.Session.create(%{
          success_url: success_url,
          line_items: subscription_items,
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
          items: item_to_delete ++ subscription_items
        })

      nil
    end
  end

  defp get_subscription_items(plan) do
    available_prices = Tuist.Environment.stripe_prices()

    usage_prices =
      available_prices[plan][:usage]
      |> Enum.map(&%{price: &1})

    flat_prices =
      available_prices[plan][:flat_monthly]
      |> Enum.map(&%{price: &1, quantity: 1})
      |> Enum.take(1)

    usage_prices ++ flat_prices
  end

  def on_subscription_change(subscription) do
    account = Accounts.get_account_from_customer_id(subscription.customer)

    plan = get_plan(subscription)
    current_subscription = Repo.get_by(Subscription, subscription_id: subscription.id)

    trial_end =
      if is_nil(Map.get(subscription, :trial_end)) do
        nil
      else
        subscription.trial_end |> DateTime.from_unix!()
      end

    cond do
      is_nil(current_subscription) ->
        Subscription.create_changeset(%Subscription{}, %{
          plan: plan,
          subscription_id: subscription.id,
          status: subscription.status,
          account_id: account.id,
          default_payment_method: subscription.default_payment_method,
          trial_end: trial_end
        })
        |> Repo.insert!()

      plan != :none ->
        Subscription.update_changeset(current_subscription, %{
          plan: plan,
          status: subscription.status,
          default_payment_method: subscription.default_payment_method,
          trial_end: trial_end
        })
        |> Repo.update!()

      plan == :none ->
        Subscription.update_changeset(current_subscription, %{
          status: subscription.status,
          default_payment_method: subscription.default_payment_method,
          trial_end: trial_end
        })
        |> Repo.update!()
    end

    :ok
  end

  defp get_plan(subscription) do
    active = subscription.status in ["active", "trialing"]
    subscription_prices = subscription.items.data |> Enum.map(& &1.price.id)
    available_prices = Tuist.Environment.stripe_prices()

    if active do
      plan =
        available_prices
        |> Enum.filter(&plan_valid?(&1, subscription_prices))
        |> Enum.map(&elem(&1, 0))
        |> List.first()

      if plan == nil, do: :none, else: plan
    else
      :none
    end
  end

  defp plan_valid?({plan, plan_prices}, subscription_prices) do
    if plan == :enterprise do
      flat = plan_prices[:flat_monthly] ++ plan_prices[:flat_yearly]
      Enum.any?(flat, &Enum.member?(subscription_prices, &1))
    else
      usage = plan_prices[:usage]
      flat = plan_prices[:flat_monthly]

      # The subscription must:
      #   - Include all the usage-based prices
      #   - Include at least one flat-based price (monthly or yearly)
      Enum.all?(usage, &Enum.member?(subscription_prices, &1)) and
        Enum.any?(flat, &Enum.member?(subscription_prices, &1))
    end
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

    card =
      if is_nil(payment_method.card),
        do: nil,
        else: %Card{
          brand: payment_method.card.brand,
          last4: payment_method.card.last4,
          exp_month: payment_method.card.exp_month,
          exp_year: payment_method.card.exp_year
        }

    %PaymentMethod{
      id: payment_method.id,
      type: payment_method.type,
      card: card
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

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def humanize_payment_method_type(type) do
    case type do
      "acss_debit" -> "ACSS Debit"
      "affirm" -> "Affirm"
      "afterpay_clearpay" -> "Afterpay/Clearpay"
      "alipay" -> "Alipay"
      "au_becs_debit" -> "AU BECS Debit"
      "bacs_debit" -> "BACS Debit"
      "bancontact" -> "Bancontact"
      "blik" -> "BLIK"
      "boleto" -> "Boleto"
      "card" -> "Card"
      "card_present" -> "Card Present"
      "cashapp" -> "Cash App"
      "customer_balance" -> "Customer Balance"
      "eps" -> "EPS"
      "fpx" -> "FPX"
      "giropay" -> "Giropay"
      "grabpay" -> "GrabPay"
      "ideal" -> "iDEAL"
      "interac_present" -> "Interac Present"
      "klarna" -> "Klarna"
      "konbini" -> "Konbini"
      "link" -> "Link"
      "oxxo" -> "OXXO"
      "p24" -> "Przelewy24"
      "paynow" -> "PayNow"
      "paypal" -> "PayPal"
      "pix" -> "PIX"
      "promptpay" -> "PromptPay"
      "revolut_pay" -> "Revolut Pay"
      "sepa_debit" -> "SEPA Debit"
      "sofort" -> "Sofort"
      "us_bank_account" -> "US Bank Account"
      "wechat_pay" -> "WeChat Pay"
      "zip" -> "Zip"
      _ -> "Unknown"
    end
  end
end
