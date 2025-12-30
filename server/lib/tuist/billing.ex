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
  alias Tuist.CommandEvents
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
        name: dgettext("dashboard_account", "Air"),
        popular: true,
        description: dgettext("dashboard_account", "Get started with no credit card required—try with no commitment."),
        price: dgettext("dashboard_account", "Free"),
        cta: {:primary, dgettext("dashboard_account", "Get started"), Tuist.Environment.get_url(:get_started)},
        features: [
          {dgettext("dashboard_account", "Generous free monthly tier"),
           dgettext("dashboard_account", "Usage capped at free tier limits")},
          {dgettext("dashboard_account", "Like, totally free"),
           dgettext("dashboard_account", "All features, no credit card required")},
          {dgettext("dashboard_account", "Community support"),
           dgettext("dashboard_account", "Support via community forum")}
        ],
        badges: [
          dgettext("dashboard_account", "No credit card required")
        ]
      },
      %{
        id: :pro,
        name: dgettext("dashboard_account", "Pro"),
        popular: false,
        description: dgettext("dashboard_account", "Usage-based pricing after free tier."),
        price: dgettext("dashboard_account", "$0"),
        price_frequency: dgettext("dashboard_account", "and up"),
        cta: {:secondary, dgettext("dashboard_account", "Get started"), Tuist.Environment.get_url(:get_started)},
        features: [
          {dgettext("dashboard_account", "Generous base price"),
           dgettext("dashboard_account", "Pay nothing if below free tier limits")},
          {dgettext("dashboard_account", "Usage-based pricing"),
           dgettext("dashboard_account", "Pay only for what you use per feature")},
          {dgettext("dashboard_account", "Standard support"), dgettext("dashboard_account", "Via Slack and email")}
        ],
        badges: [
          dgettext("dashboard_account", "Unlimited projects")
        ]
      },
      %{
        id: :enterprise,
        name: dgettext("dashboard_account", "Enterprise"),
        popular: false,
        description: dgettext("dashboard_account", "Create your plan or self-host your instance."),
        price: dgettext("dashboard_account", "Custom"),
        cta: {:secondary, dgettext("dashboard_account", "Contact sales"), "mailto:contact@tuist.dev"},
        features: [
          {dgettext("dashboard_account", "Custom terms"),
           dgettext("dashboard_account", "Tailored agreements to meet your specific needs")},
          {dgettext("dashboard_account", "On-premise"),
           dgettext("dashboard_account", "Self-host your instance of Tuist")},
          {dgettext("dashboard_account", "Priority support"), dgettext("dashboard_account", "Via shared Slack channel")}
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

  def update_remote_cache_hit_meter(customer_id, idempotency_key) do
    count = CommandEvents.get_yesterdays_remote_cache_hits_count_for_customer(customer_id)
    path = Stripe.OpenApi.Path.replace_path_params("/v1/billing/meter_events", [], [])

    identifier =
      "#{customer_id}-#{Timex.format!(Tuist.Time.utc_now(), "{YYYY}.{0M}.{D}")}"

    {:ok, _} =
      []
      |> Stripe.Request.new_request(%{"Idempotency-Key" => "#{idempotency_key}-remote-cache-hit"})
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
    case Accounts.get_account_from_customer_id(subscription.customer) do
      {:error, :not_found} ->
        # We had a race-condition that caused multiple customers to be created on Stripe
        # for the same account. Because of that, we were getting webhooks for customers
        # that we couldn't look up in our database. Until we sync the customers, we'll
        # ignore the webhooks for those customers.
        :ok

      {:ok, account} ->
        on_subscription_change_for_account(subscription, account)
    end
  end

  defp on_subscription_change_for_account(subscription, account) do
    plan = get_plan(subscription)
    current_subscription = Repo.get_by(Subscription, subscription_id: subscription.id)

    trial_end =
      if is_nil(Map.get(subscription, :trial_end)) do
        nil
      else
        DateTime.from_unix!(subscription.trial_end)
      end

    cond do
      plan == :none ->
        raise "Unable to determine plan from subscription items. Subscription ID: #{subscription.id}, Price IDs: #{inspect(Enum.map(subscription.items.data, & &1.price.id))}"

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

      true ->
        current_subscription
        |> Subscription.update_changeset(%{
          plan: plan,
          status: subscription.status,
          default_payment_method: subscription.default_payment_method,
          trial_end: trial_end
        })
        |> Repo.update!()
    end

    :ok
  end

  defp get_plan(subscription) do
    subscription_prices = Enum.map(subscription.items.data, & &1.price.id)
    available_prices = Tuist.Environment.stripe_prices()

    plan =
      available_prices
      |> Enum.filter(&plan_valid?(&1, subscription_prices))
      |> Enum.map(&elem(&1, 0))
      |> List.first()

    if plan == nil, do: :none, else: plan
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
          average_tokens:
            fragment(
              "CASE WHEN count(distinct ?) > 0 THEN (coalesce(sum(?), 0) + coalesce(sum(?), 0)) / count(distinct ?) ELSE 0 END",
              tu.feature_resource_id,
              tu.input_tokens,
              tu.output_tokens,
              tu.feature_resource_id
            ),
          total_tokens: coalesce(sum(tu.input_tokens), 0) + coalesce(sum(tu.output_tokens), 0)
        }
      )

    case Repo.one(query) do
      nil -> %{total_input_tokens: 0, total_output_tokens: 0, average_tokens: 0, total_tokens: 0}
      result -> result
    end
  end

  @doc """
  Gets token usage for all accounts for a specific feature, with 30-day and 12-month stats.
  """
  def feature_token_usage_by_account(feature) do
    thirty_days_ago = DateTime.add(DateTime.utc_now(), -30, :day)
    twelve_months_ago = DateTime.add(DateTime.utc_now(), -365, :day)

    query =
      from(tu in TokenUsage,
        join: a in assoc(tu, :account),
        where: tu.feature == ^feature and tu.timestamp >= ^twelve_months_ago,
        group_by: [tu.account_id, a.name],
        select: %{
          account_id: tu.account_id,
          account_name: a.name,
          twelve_month_total_input_tokens: coalesce(sum(tu.input_tokens), 0),
          twelve_month_total_output_tokens: coalesce(sum(tu.output_tokens), 0),
          twelve_month_total_tokens: coalesce(sum(tu.input_tokens), 0) + coalesce(sum(tu.output_tokens), 0),
          twelve_month_average_tokens:
            fragment(
              "CASE WHEN count(distinct ?) > 0 THEN (coalesce(sum(?), 0) + coalesce(sum(?), 0)) / count(distinct ?) ELSE 0 END",
              tu.feature_resource_id,
              tu.input_tokens,
              tu.output_tokens,
              tu.feature_resource_id
            ),
          thirty_day_total_input_tokens:
            coalesce(
              sum(
                fragment(
                  "CASE WHEN ? >= ? THEN ? ELSE 0 END",
                  tu.timestamp,
                  ^thirty_days_ago,
                  tu.input_tokens
                )
              ),
              0
            ),
          thirty_day_total_output_tokens:
            coalesce(
              sum(
                fragment(
                  "CASE WHEN ? >= ? THEN ? ELSE 0 END",
                  tu.timestamp,
                  ^thirty_days_ago,
                  tu.output_tokens
                )
              ),
              0
            ),
          thirty_day_total_tokens:
            coalesce(
              sum(
                fragment(
                  "CASE WHEN ? >= ? THEN ? ELSE 0 END",
                  tu.timestamp,
                  ^thirty_days_ago,
                  tu.input_tokens
                )
              ),
              0
            ) +
              coalesce(
                sum(
                  fragment(
                    "CASE WHEN ? >= ? THEN ? ELSE 0 END",
                    tu.timestamp,
                    ^thirty_days_ago,
                    tu.output_tokens
                  )
                ),
                0
              ),
          thirty_day_average_tokens:
            fragment(
              "CASE WHEN count(distinct CASE WHEN ? >= ? THEN ? END) > 0 THEN (coalesce(sum(CASE WHEN ? >= ? THEN ? ELSE 0 END), 0) + coalesce(sum(CASE WHEN ? >= ? THEN ? ELSE 0 END), 0)) / count(distinct CASE WHEN ? >= ? THEN ? END) ELSE 0 END",
              tu.timestamp,
              ^thirty_days_ago,
              tu.feature_resource_id,
              tu.timestamp,
              ^thirty_days_ago,
              tu.input_tokens,
              tu.timestamp,
              ^thirty_days_ago,
              tu.output_tokens,
              tu.timestamp,
              ^thirty_days_ago,
              tu.feature_resource_id
            )
        }
      )

    query
    |> Repo.all()
    |> Enum.map(fn result ->
      %{
        account_id: result.account_id,
        account_name: result.account_name,
        twelve_month: %{
          total_input_tokens: result.twelve_month_total_input_tokens,
          total_output_tokens: result.twelve_month_total_output_tokens,
          total_tokens: result.twelve_month_total_tokens,
          average_tokens: result.twelve_month_average_tokens
        },
        thirty_day: %{
          total_input_tokens: result.thirty_day_total_input_tokens,
          total_output_tokens: result.thirty_day_total_output_tokens,
          total_tokens: result.thirty_day_total_tokens,
          average_tokens: result.thirty_day_average_tokens
        }
      }
    end)
    |> Enum.sort_by(& &1.twelve_month.total_tokens, :desc)
  end

  @doc """
  Gets LLM token usage for a specific customer for the current billing period (yesterday).
  Returns {input_tokens, output_tokens}.
  """
  def get_yesterdays_customer_llm_token_usage(customer_id) do
    now = DateTime.utc_now()
    start_of_yesterday = now |> Timex.shift(days: -1) |> Timex.beginning_of_day()
    end_of_yesterday = now |> Timex.shift(days: -1) |> Timex.end_of_day()

    Repo.one(
      from(tu in TokenUsage,
        join: a in assoc(tu, :account),
        where:
          a.customer_id == ^customer_id and tu.timestamp >= ^start_of_yesterday and
            tu.timestamp <= ^end_of_yesterday,
        select: {sum(tu.input_tokens), sum(tu.output_tokens)}
      )
    )
  end

  @doc """
  Updates both LLM input and output token usage meters in Stripe for a specific customer.
  Fetches the current period token usage and updates both meters.
  """
  def update_llm_token_meters(customer_id, idempotency_key) do
    {input_tokens, output_tokens} = get_yesterdays_customer_llm_token_usage(customer_id)
    path = Stripe.OpenApi.Path.replace_path_params("/v1/billing/meter_events", [], [])

    input_identifier =
      "#{customer_id}-input-#{Timex.format!(Tuist.Time.utc_now(), "{YYYY}.{0M}.{D}")}"

    {:ok, _} =
      []
      |> Stripe.Request.new_request(%{"Idempotency-Key" => "#{idempotency_key}-input"})
      |> Stripe.Request.put_endpoint(path)
      |> Stripe.Request.put_params(%{
        event_name: "llm_input_token",
        identifier: input_identifier,
        payload: %{
          value: input_tokens,
          stripe_customer_id: customer_id
        }
      })
      |> Stripe.Request.put_method(:post)
      |> Stripe.Request.make_request()

    output_identifier =
      "#{customer_id}-output-#{Timex.format!(Tuist.Time.utc_now(), "{YYYY}.{0M}.{D}")}"

    {:ok, _} =
      []
      |> Stripe.Request.new_request(%{"Idempotency-Key" => "#{idempotency_key}-output"})
      |> Stripe.Request.put_endpoint(path)
      |> Stripe.Request.put_params(%{
        event_name: "llm_output_token",
        identifier: output_identifier,
        payload: %{
          value: output_tokens,
          stripe_customer_id: customer_id
        }
      })
      |> Stripe.Request.put_method(:post)
      |> Stripe.Request.make_request()
  end

  @doc """
  Fetches Namespace compute usage for yesterday and updates the Stripe meter
  for instance unit minutes (event name: `namespace_unit_minute`).
  """
  def update_namespace_usage_meter(customer_id, idempotency_key) do
    with {:ok, %Account{namespace_tenant_id: namespace_tenant_id} = account}
         when is_binary(namespace_tenant_id) <-
           Accounts.get_account_from_customer_id(customer_id) do
      # Namespace compute usage is reported by day, so being more specific than `Date` is unnecessary.
      yesterday = Date.add(Date.utc_today(), -1)

      with {:ok, %{"total" => total}} <-
             Tuist.Namespace.get_tenant_usage(account, yesterday, yesterday) do
        instance_unit_minutes = get_in(total, ["instanceMinutes", "unit"]) || 0

        path = Stripe.OpenApi.Path.replace_path_params("/v1/billing/meter_events", [], [])

        identifier =
          "#{customer_id}-namespace-#{Timex.format!(Tuist.Time.utc_now(), "{YYYY}.{0M}.{D}")}"

        {:ok, _} =
          []
          |> Stripe.Request.new_request(%{"Idempotency-Key" => "#{idempotency_key}-namespace"})
          |> Stripe.Request.put_endpoint(path)
          |> Stripe.Request.put_params(%{
            event_name: "namespace_unit_minute",
            identifier: identifier,
            payload: %{
              value: instance_unit_minutes,
              stripe_customer_id: customer_id
            }
          })
          |> Stripe.Request.put_method(:post)
          |> Stripe.Request.make_request()

        {:ok, :updated}
      end
    end
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
