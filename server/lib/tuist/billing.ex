defmodule Tuist.Billing do
  @moduledoc """
  A module for operations related to billing.
  """
  use Gettext, backend: TuistWeb.Gettext

  import Ecto.Query, only: [from: 2]

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Billing.Card
  alias Tuist.Billing.Customer
  alias Tuist.Billing.PaymentMethod
  alias Tuist.Billing.Subscription
  alias Tuist.Billing.TokenUsage
  alias Tuist.Repo

  # Unfortunately, this data can't be obtained and cached
  # from the Stripe's API, so we have to make sure it's in sync
  # with the values on Stripe.
  @payment_thresholds %{remote_cache_hits: 200}
  @unit_prices %{remote_cache_hit: Money.new(50, :USD)}

  def get_payment_thresholds do
    @payment_thresholds
  end

  def get_unit_prices do
    @unit_prices
  end

  def get_plans do
    [
      %{
        id: :air,
        name: gettext("Air"),
        popular: true,
        description: gettext("Get started with no credit card required—try with no commitment."),
        price: gettext("Free"),
        cta: {:primary, gettext("Get started"), Tuist.Environment.get_url(:get_started)},
        features: [
          {gettext("Generous free monthly tier"), gettext("Usage capped at free tier limits")},
          {gettext("Like, totally free"), gettext("All features, no credit card required")},
          {gettext("Community support"), gettext("Support via community forum")}
        ],
        badges: [
          gettext("No credit card required")
        ]
      },
      %{
        id: :pro,
        name: gettext("Pro"),
        popular: false,
        description: gettext("Usage-based pricing after free tier."),
        price: gettext("$0"),
        price_frequency: gettext("and up"),
        cta: {:secondary, gettext("Get started"), Tuist.Environment.get_url(:get_started)},
        features: [
          {gettext("Generous base price"), gettext("Pay nothing if below free tier limits")},
          {gettext("Usage-based pricing"), gettext("Pay only for what you use per feature")},
          {gettext("Standard support"), gettext("Via Slack and email")}
        ],
        badges: [
          gettext("Unlimited projects")
        ]
      },
      %{
        id: :enterprise,
        name: gettext("Enterprise"),
        popular: false,
        description: gettext("Create your plan or self-host your instance."),
        price: gettext("Custom"),
        cta: {:secondary, gettext("Contact sales"), "mailto:contact@tuist.dev"},
        features: [
          {gettext("Custom terms"), gettext("Tailored agreements to meet your specific needs")},
          {gettext("On-premise"), gettext("Self-host your instance of Tuist")},
          {gettext("Priority support"), gettext("Via shared Slack channel")}
        ],
        badges: []
      }
    ]
  end

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
      "#{customer_id}-#{Timex.format!(Tuist.Time.utc_now(), "{YYYY}.{0M}.{D}")}"

    {:ok, _} =
      []
      |> Stripe.Request.new_request()
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

  def update_plan(%{plan: plan, account: %Account{} = account, success_url: success_url}) do
    customer_id = account.customer_id

    current_subscription = get_current_active_subscription(account)

    subscription_items = get_subscription_items(to_string(plan))

    if is_nil(current_subscription) do
      {:ok, session} =
        Stripe.Checkout.Session.create(%{
          success_url: success_url,
          line_items: subscription_items,
          mode: "subscription",
          customer: customer_id
        })

      {:ok, {:external_redirect, session.url}}
    else
      {:ok, stripe_subscription} =
        Stripe.Subscription.retrieve(current_subscription.subscription_id)

      item_to_delete = Enum.map(stripe_subscription.items.data, &%{id: &1.id, deleted: true})

      {:ok, _} =
        Stripe.Subscription.update(current_subscription.subscription_id, %{
          items: item_to_delete ++ subscription_items
        })

      :ok
    end
  end

  defp get_subscription_items(plan) do
    available_prices = Tuist.Environment.stripe_prices()

    usage_prices = Enum.map(available_prices[plan]["usage"], &%{price: &1})

    flat_prices =
      available_prices[plan]["flat_monthly"]
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
        DateTime.from_unix!(subscription.trial_end)
      end

    cond do
      is_nil(account) ->
        # We had a race-condition that caused multiple customers to be created on Stripe
        # for the same account. Because of that, we were getting webhooks for customers
        # that we couldn't look up in our database. Until we sync the customers, we'll
        # ignore the webhooks for those customers.
        :ok

      is_nil(current_subscription) ->
        %Subscription{}
        |> Subscription.create_changeset(%{
          plan: plan,
          subscription_id: subscription.id,
          status: subscription.status,
          account_id: account.id,
          default_payment_method: subscription.default_payment_method,
          trial_end: trial_end
        })
        |> Repo.insert!()

      plan != :none ->
        current_subscription
        |> Subscription.update_changeset(%{
          plan: plan,
          status: subscription.status,
          default_payment_method: subscription.default_payment_method,
          trial_end: trial_end
        })
        |> Repo.update!()

      plan == :none ->
        current_subscription
        |> Subscription.update_changeset(%{
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
    subscription_prices = Enum.map(subscription.items.data, & &1.price.id)
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
    if plan == "enterprise" do
      flat = plan_prices["flat_monthly"] ++ plan_prices["flat_yearly"]
      Enum.any?(flat, &Enum.member?(subscription_prices, &1))
    else
      usage = plan_prices["usage"]
      flat = plan_prices["flat_monthly"]

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

  def get_estimated_next_payment(%{current_month_remote_cache_hits_count: current_month_remote_cache_hits_count}) do
    remote_cache_hits_threshold = get_payment_thresholds()[:remote_cache_hits]

    if current_month_remote_cache_hits_count < remote_cache_hits_threshold do
      0 |> Money.new(:USD) |> Money.to_string()
    else
      get_unit_prices()[:remote_cache_hit]
      |> Money.multiply(current_month_remote_cache_hits_count - remote_cache_hits_threshold)
      |> Money.to_string()
    end
  end

  def get_subscription_current_period_end(subscription_id) do
    {:ok, %{current_period_end: current_period_end}} =
      Stripe.Subscription.retrieve(subscription_id)

    DateTime.from_unix!(current_period_end)
  end

  def get_payment_method_id_from_subscription_id(subscription_id) do
    with {:ok, %{default_payment_method: nil, customer: customer_id}} <-
           Stripe.Subscription.retrieve(subscription_id),
         {:ok, %{invoice_settings: %{default_payment_method: payment_method}}} <-
           Stripe.Customer.retrieve(customer_id) do
      payment_method
    else
      {:ok, %{default_payment_method: payment_method}} when not is_nil(payment_method) ->
        payment_method

      _ ->
        nil
    end
  end

  def get_payment_method_by_id(payment_method_id) do
    {:ok, payment_method} = Stripe.PaymentMethod.retrieve(payment_method_id)

    card =
      if is_nil(payment_method.card),
        do: nil,
        else: %Card{
          cardholder_name: payment_method.billing_details.name,
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
    Repo.one(
      from(s in Subscription,
        where: s.account_id == ^account.id,
        where: s.status == "active" or s.status == "trialing",
        order_by: [desc: s.inserted_at],
        limit: 1
      )
    )
  end

  @doc """
  Creates a new token usage record for billing purposes.
  """
  def create_token_usage(attrs) do
    %TokenUsage{}
    |> TokenUsage.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets token usage statistics for a specific feature and resource.
  """
  def token_usage_for_resource(feature, resource_id) do
    query =
      from(tu in TokenUsage,
        where: tu.feature == ^feature and tu.feature_resource_id == ^resource_id,
        select: %{
          total_input_tokens: coalesce(sum(tu.input_tokens), 0),
          total_output_tokens: coalesce(sum(tu.output_tokens), 0),
          usage_count: count(tu.id),
          total_tokens: coalesce(sum(tu.input_tokens), 0) + coalesce(sum(tu.output_tokens), 0)
        }
      )

    case Repo.one(query) do
      nil -> %{total_input_tokens: 0, total_output_tokens: 0, usage_count: 0, total_tokens: 0}
      result -> result
    end
  end

  @doc """
  Gets token usage for all accounts for a specific feature, with 30-day and all-time stats.
  """
  def feature_token_usage_by_account(feature) do
    thirty_days_ago = DateTime.add(DateTime.utc_now(), -30, :day)

    all_time_query =
      from(tu in TokenUsage,
        join: a in assoc(tu, :account),
        where: tu.feature == ^feature,
        group_by: [tu.account_id, a.name],
        select: %{
          account_id: tu.account_id,
          account_name: a.name,
          total_input_tokens: coalesce(sum(tu.input_tokens), 0),
          total_output_tokens: coalesce(sum(tu.output_tokens), 0),
          total_tokens: coalesce(sum(tu.input_tokens), 0) + coalesce(sum(tu.output_tokens), 0),
          usage_count: count(tu.id)
        }
      )

    thirty_day_query =
      from(tu in TokenUsage,
        join: a in assoc(tu, :account),
        where: tu.feature == ^feature and tu.timestamp >= ^thirty_days_ago,
        group_by: [tu.account_id, a.name],
        select: %{
          account_id: tu.account_id,
          account_name: a.name,
          total_input_tokens: coalesce(sum(tu.input_tokens), 0),
          total_output_tokens: coalesce(sum(tu.output_tokens), 0),
          total_tokens: coalesce(sum(tu.input_tokens), 0) + coalesce(sum(tu.output_tokens), 0),
          usage_count: count(tu.id)
        }
      )

    all_time_results = Repo.all(all_time_query)
    thirty_day_results = Repo.all(thirty_day_query)

    thirty_day_map =
      Map.new(thirty_day_results, fn result -> {result.account_id, result} end)

    all_time_results
    |> Enum.map(fn all_time ->
      thirty_day =
        Map.get(thirty_day_map, all_time.account_id, %{
          total_input_tokens: 0,
          total_output_tokens: 0,
          total_tokens: 0,
          usage_count: 0
        })

      %{
        account_id: all_time.account_id,
        account_name: all_time.account_name,
        all_time: %{
          total_input_tokens: all_time.total_input_tokens,
          total_output_tokens: all_time.total_output_tokens,
          total_tokens: all_time.total_tokens,
          usage_count: all_time.usage_count
        },
        thirty_day: %{
          total_input_tokens: thirty_day.total_input_tokens,
          total_output_tokens: thirty_day.total_output_tokens,
          total_tokens: thirty_day.total_tokens,
          usage_count: thirty_day.usage_count
        }
      }
    end)
    |> Enum.sort_by(& &1.all_time.total_tokens, :desc)
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
