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
  alias Tuist.Runners.Billing, as: RunnerBilling

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

  @doc """
  Snapshots every meter value for one customer and one immutable
  half-open billing period `[period_start, period_end)`. The caller
  can enqueue each returned value as an independent Stripe reporting
  job without recalculating usage when that job retries.
  """
  def customer_meter_values(
        %Account{customer_id: customer_id, id: account_id},
        %DateTime{} = period_start,
        %DateTime{} = period_end,
        opts \\ []
      ) do
    remote_cache_values = [
      %{
        event_name: "remote_cache_hit",
        value: CommandEvents.remote_cache_hits_count_for_customer(customer_id, period_start, period_end) || 0
      }
    ]

    language_model_values =
      if Keyword.get(opts, :include_qa, false) do
        {input_tokens, output_tokens} = customer_llm_token_usage(customer_id, period_start, period_end)

        [
          %{event_name: "llm_input_token", value: input_tokens},
          %{event_name: "llm_output_token", value: output_tokens}
        ]
      else
        []
      end

    # Only report runner meters whose Stripe price is configured. During
    # the staged rollout `stripe.prices.runners` is empty, so no runner
    # meters exist in Stripe yet; reporting to an unprovisioned meter just
    # errors the job and adds Sentry noise, and usage without an attached
    # price wouldn't bill anyway. Each platform turns on the moment its
    # price lands in config.
    runner_prices = Map.get(Tuist.Environment.stripe_prices() || %{}, "runners", %{})

    runner_values =
      account_id
      |> RunnerBilling.compute_units_by_platform(period_start, period_end)
      |> Enum.map(fn usage ->
        %{event_name: RunnerBilling.meter_event_name(usage), value: usage.total_units}
      end)
      |> Enum.filter(&runner_meter_priced?(runner_prices, &1.event_name))

    # Drop zero-value meters uniformly so an idle customer fans out no
    # Stripe reporting jobs at all, rather than one no-op POST per meter.
    Enum.reject(remote_cache_values ++ language_model_values ++ runner_values, &(&1.value == 0))
  end

  defp runner_meter_priced?(runner_prices, event_name) do
    case Map.get(runner_prices, event_name) do
      price when is_binary(price) and price != "" -> true
      _ -> false
    end
  end

  @doc """
  Half-open reporting windows covering `[period_start, period_end)`,
  split at the account's subscription renewal boundary when one falls
  inside the window.

  A meter event carries a single timestamp, so a UTC-day aggregate that
  straddles a renewal would have to be attributed entirely to one side
  of the boundary or the other. Splitting first means every event we
  send lies wholly within one service period, and the value reported is
  exactly the usage that period earned. Renewals are the only boundary
  that can fall inside a one-day window, and there can be at most one.

  Falls back to the whole window when the account has no active
  subscription or Stripe can't be reached: over-reporting into the
  current period is better than dropping the day entirely, and a
  customer with no subscription has nothing to invoice against anyway.
  """
  def usage_windows(%Account{} = account, %DateTime{} = period_start, %DateTime{} = period_end) do
    case renewal_boundary(account) do
      %DateTime{} = boundary ->
        if DateTime.after?(boundary, period_start) and DateTime.before?(boundary, period_end) do
          [{period_start, boundary}, {boundary, period_end}]
        else
          [{period_start, period_end}]
        end

      nil ->
        [{period_start, period_end}]
    end
  end

  defp renewal_boundary(%Account{} = account) do
    case get_current_active_subscription(account) do
      %Subscription{subscription_id: subscription_id} when is_binary(subscription_id) ->
        case Stripe.Subscription.retrieve(subscription_id) do
          {:ok, %{current_period_start: current_period_start}} when is_integer(current_period_start) ->
            DateTime.from_unix!(current_period_start)

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  @doc """
  Reports one previously-snapshotted value to Stripe. The event
  identifier and request idempotency key both include the parent
  period, so a retried child job reports the same value under the same
  identifier and Stripe deduplicates it rather than double-counting.

  The event is stamped just inside the end of its own usage window, so
  Stripe attributes it to the service period the usage actually
  happened in. Letting Stripe default the timestamp to ingestion time
  would move a day of usage into whichever period happened to be open
  when the job ran, which breaks down at a renewal, at a mid-cycle
  price change, and worst of all at `cancel_at_period_end`, where there
  is no following invoice for the shifted usage to land on.

  This makes the reporting delay matter: an event stamped inside a
  period that has already finalized is never billed. `usage_windows/3`
  keeps each event inside one period, and Stripe's invoice
  finalization grace period (Billing settings, up to 72 hours) has to
  cover the gap between period close and this daily job.

  Returns `{:ok, :already_reported}` when Stripe rejects the event as a
  duplicate, so the caller treats it as delivered instead of retrying.
  """
  def report_meter_event(customer_id, event_name, value, %DateTime{} = period_start, %DateTime{} = period_end)
      when is_binary(customer_id) and is_binary(event_name) and is_integer(value) and value >= 0 do
    identifier =
      "#{customer_id}-#{event_name}-#{DateTime.to_unix(period_start)}-#{DateTime.to_unix(period_end)}"

    []
    |> Stripe.Request.new_request(%{"Idempotency-Key" => identifier})
    |> Stripe.Request.put_endpoint(Stripe.OpenApi.Path.replace_path_params("/v1/billing/meter_events", [], []))
    |> Stripe.Request.put_params(%{
      event_name: event_name,
      identifier: identifier,
      timestamp: DateTime.to_unix(usage_timestamp(period_start, period_end)),
      payload: %{
        value: value,
        stripe_customer_id: customer_id
      }
    })
    |> Stripe.Request.put_method(:post)
    |> Stripe.Request.make_request()
    |> resolve_duplicate()
  end

  # A rejected duplicate means Stripe already has this exact event, which
  # is the outcome we wanted. Retrying it would only burn attempts and,
  # once the dedup window lapses, risk landing a second copy. Stripe
  # doesn't document a stable error code for this, so match on the
  # identifier-conflict shape and let anything else stay an error.
  defp resolve_duplicate({:error, %Stripe.Error{code: code, message: message} = error})
       when code in [:invalid_request_error, :conflict, :bad_request] do
    if is_binary(message) and String.contains?(message, "identifier") and
         String.contains?(String.downcase(message), ["already", "duplicate"]) do
      {:ok, :already_reported}
    else
      {:error, error}
    end
  end

  defp resolve_duplicate(result), do: result

  # The window is half-open, so `period_end` itself belongs to the next
  # service period. Stamp one second earlier to stay inside this one,
  # clamping up to `period_start` for windows shorter than a second.
  defp usage_timestamp(period_start, period_end) do
    timestamp = DateTime.add(period_end, -1, :second)

    if DateTime.before?(timestamp, period_start), do: period_start, else: timestamp
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

    usage_prices =
      available_prices[plan]["usage"]
      |> List.wrap()
      |> Enum.map(&%{price: &1})

    flat_prices =
      available_prices[plan]["flat_monthly"]
      |> List.wrap()
      |> Enum.map(&%{price: &1, quantity: 1})
      |> Enum.take(1)

    usage_prices ++ runner_subscription_items(available_prices) ++ flat_prices
  end

  @doc """
  Creates or switches the subscription to enterprise with
  `collection_method: send_invoice`, so the customer is invoice-billed and no
  card/Stripe Checkout redirect is required.

  When `params` contains billing details (`:name`, `:billing_email`,
  `:address`), the Stripe customer is updated first. Callers that already
  have a customer with those details on file can pass just `%{cadence: ...}`.
  """
  def upgrade_to_enterprise(%Account{} = account, params) do
    account = Accounts.create_customer_when_absent(account)

    if Map.has_key?(params, :address) do
      {:ok, _customer} =
        Stripe.Customer.update(account.customer_id, %{
          name: params.name,
          email: params.billing_email,
          address: params.address
        })
    end

    subscription_items = enterprise_subscription_items(Map.get(params, :cadence, "monthly"))
    current_subscription = get_current_active_subscription(account)

    stripe_sub =
      if is_nil(current_subscription) do
        {:ok, sub} =
          Stripe.Subscription.create(%{
            customer: account.customer_id,
            items: subscription_items,
            collection_method: "send_invoice",
            days_until_due: Map.get(params, :days_until_due, 30)
          })

        sub
      else
        {:ok, current_stripe_sub} = Stripe.Subscription.retrieve(current_subscription.subscription_id)
        items_to_delete = Enum.map(current_stripe_sub.items.data, &%{id: &1.id, deleted: true})

        {:ok, sub} =
          Stripe.Subscription.update(current_subscription.subscription_id, %{
            items: items_to_delete ++ subscription_items,
            collection_method: "send_invoice",
            days_until_due: Map.get(params, :days_until_due, 30)
          })

        sub
      end

    on_subscription_change(stripe_sub)
    {:ok, stripe_sub}
  end

  defp enterprise_subscription_items(cadence) do
    available_prices = Tuist.Environment.stripe_prices()
    key = if cadence == "yearly", do: "flat_yearly", else: "flat_monthly"

    usage_prices =
      available_prices["enterprise"]["usage"]
      |> List.wrap()
      |> Enum.map(&%{price: &1})

    # Enterprise is negotiated per-deal; start the subscription with 0 seats
    # so sales can fill in the actual quantity on Stripe without us guessing.
    flat_prices =
      available_prices["enterprise"][key]
      |> List.wrap()
      |> Enum.take(1)
      |> Enum.map(&%{price: &1, quantity: 0})

    usage_prices ++ runner_subscription_items(available_prices) ++ flat_prices
  end

  defp runner_subscription_items(available_prices) do
    available_prices
    |> Map.get("runners", %{})
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.flat_map(fn
      {_meter_event_name, price_id} when is_binary(price_id) and price_id != "" -> [%{price: price_id}]
      _ -> []
    end)
  end

  @doc """
  Flags an active Stripe subscription to cancel at the end of the current
  billing period. The local DB row keeps its `active`/`trialing` status until
  Stripe emits the cancellation event at period end; we don't mark it cancelled
  up-front because the customer still has access.
  """
  def cancel_subscription_at_period_end(%Subscription{} = subscription) do
    Stripe.Subscription.update(subscription.subscription_id, %{cancel_at_period_end: true})
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
          trial_end: trial_end,
          cancel_at_period_end: Map.get(subscription, :cancel_at_period_end, false) || false
        })
        |> Repo.insert!()

      true ->
        current_subscription
        |> Subscription.update_changeset(%{
          plan: plan,
          status: subscription.status,
          default_payment_method: subscription.default_payment_method,
          trial_end: trial_end,
          cancel_at_period_end: Map.get(subscription, :cancel_at_period_end, false) || false
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
      |> Enum.filter(fn prices ->
        plan_prices?(prices) and plan_valid?(prices, subscription_prices)
      end)
      |> Enum.map(&elem(&1, 0))
      |> List.first()

    if plan == nil, do: :none, else: plan
  end

  defp plan_prices?({_plan, prices}) do
    is_map(prices) and Map.has_key?(prices, "flat_monthly")
  end

  defp plan_valid?({plan, plan_prices}, subscription_prices) do
    if plan == "enterprise" do
      flat = List.wrap(plan_prices["flat_monthly"]) ++ List.wrap(plan_prices["flat_yearly"])
      Enum.any?(flat, &Enum.member?(subscription_prices, &1))
    else
      usage = List.wrap(plan_prices["usage"])
      flat = List.wrap(plan_prices["flat_monthly"])

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

  def get_estimated_next_payment_money(%{current_month_remote_cache_hits_count: current_month_remote_cache_hits_count}) do
    remote_cache_hits_threshold = get_payment_thresholds()[:remote_cache_hits]

    if current_month_remote_cache_hits_count < remote_cache_hits_threshold do
      Money.new(0, :USD)
    else
      Money.multiply(
        get_unit_prices()[:remote_cache_hit],
        current_month_remote_cache_hits_count - remote_cache_hits_threshold
      )
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
  Gets language-model token usage for a customer within the supplied
  half-open billing period. Returns `{input_tokens, output_tokens}`.
  """
  def customer_llm_token_usage(customer_id, %DateTime{} = period_start, %DateTime{} = period_end) do
    Repo.one(
      from(tu in TokenUsage,
        join: a in assoc(tu, :account),
        where:
          a.customer_id == ^customer_id and tu.timestamp >= ^period_start and
            tu.timestamp < ^period_end,
        select: {coalesce(sum(tu.input_tokens), 0), coalesce(sum(tu.output_tokens), 0)}
      )
    )
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
