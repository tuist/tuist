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
  alias Tuist.Runners.Trials

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

    # Only report a platform's runner meter once that Meter exists in
    # Stripe. During the staged rollout `stripe.prices.runners` is empty,
    # so neither Meter exists yet, and reporting to an unprovisioned meter
    # just errors the job and adds Sentry noise. Each platform turns on
    # independently, the moment its key lands in config.
    runner_values =
      account_id
      |> RunnerBilling.compute_units_by_platform(period_start, period_end)
      |> Enum.map(fn usage ->
        %{event_name: RunnerBilling.meter_event_name(usage.platform), value: usage.total_units}
      end)
      |> Enum.filter(&runner_meter_provisioned?(&1.event_name))

    # Drop zero-value meters uniformly so an idle customer fans out no
    # Stripe reporting jobs at all, rather than one no-op POST per meter.
    Enum.reject(remote_cache_values ++ language_model_values ++ runner_values, &(&1.value == 0))
  end

  # A platform reports as soon as its Meter exists in Stripe, which the
  # presence of its key in `stripe.prices.runners` declares. The value is
  # the Price id, and an empty one is the deliberate reporting-only state:
  # usage accrues on the Meter where it can be inspected, while
  # `runner_subscription_items/1` and `configured_runner_price_ids/0` both
  # skip empty ids, so no subscription ever carries the item and nothing
  # can be charged. Filling the id in is what turns billing on.
  defp runner_meter_provisioned?(event_name) do
    (Tuist.Environment.stripe_prices() || %{})
    |> Map.get("runners", %{})
    |> Map.has_key?(event_name)
  end

  @doc """
  Half-open reporting windows covering `[period_start, period_end)`,
  split at every service-period boundary that falls inside it.

  A meter event carries a single timestamp, so a UTC-day aggregate that
  straddles a boundary would have to be attributed entirely to one side
  of it. Splitting first means every event we send lies wholly within one
  service period, and the value reported is exactly the usage that period
  earned.

  Two kinds of boundary can land inside a one-day window:

    * a renewal, which opens a new cycle (`current_period_start`)
    * the end of service, either already reached (`ended_at`) or
      scheduled by `cancel_at_period_end` (`cancel_at`)

  The cancellation end matters most. Usage on the final day would
  otherwise be stamped near the end of the UTC day — after the
  subscription ended — and miss the final invoice, with no following
  invoice to catch it. Splitting at that instant puts the pre-cancellation
  portion inside the final period.

  Boundary discovery therefore looks at the account's most recent
  subscription regardless of status: at `cancel_at_period_end` the local
  row is no longer active or trialing, yet its final cycle is exactly the
  one being reported.

  Returns `{:ok, windows}`, or `{:error, reason}` when Stripe cannot be
  reached. An unknown boundary is not the same as no boundary: on a
  renewal or cancellation day, treating it as none would permanently
  snapshot an unsplit value and attribute the earlier portion to the wrong
  period. The caller retries instead. An account with no subscription at
  all is not an error — it has nothing to invoice against, and the whole
  window is reported as one.
  """
  def usage_windows(%Account{} = account, %DateTime{} = period_start, %DateTime{} = period_end) do
    case service_period_boundaries(account) do
      {:ok, boundaries} ->
        {:ok, split_window(period_start, period_end, boundaries)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp split_window(period_start, period_end, boundaries) do
    cuts =
      boundaries
      |> Enum.filter(&(DateTime.after?(&1, period_start) and DateTime.before?(&1, period_end)))
      |> Enum.uniq_by(&DateTime.to_unix(&1, :microsecond))
      |> Enum.sort(DateTime)

    Enum.zip([period_start | cuts], cuts ++ [period_end])
  end

  defp service_period_boundaries(%Account{} = account) do
    case latest_subscription_for_boundaries(account) do
      %Subscription{subscription_id: subscription_id} when is_binary(subscription_id) ->
        case Stripe.Subscription.retrieve(subscription_id) do
          {:ok, stripe_subscription} -> {:ok, boundaries_from_stripe(stripe_subscription)}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:ok, []}
    end
  end

  # `cancel_at` is what `cancel_at_period_end` schedules, and `ended_at` is
  # what Stripe stamps once the subscription actually ends; taking both
  # covers the day before and the day after the cancellation lands.
  defp boundaries_from_stripe(stripe_subscription) do
    [:current_period_start, :cancel_at, :ended_at]
    |> Enum.map(&Map.get(stripe_subscription, &1))
    |> Enum.filter(&is_integer/1)
    |> Enum.map(&DateTime.from_unix!/1)
  end

  defp latest_subscription_for_boundaries(%Account{} = account) do
    Repo.one(
      from(s in Subscription,
        where: s.account_id == ^account.id,
        order_by: [desc: s.inserted_at, desc: s.id],
        limit: 1
      )
    )
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

  `reported_at` is the instant the reporting work was enqueued, not the
  current time. It must be identical on every attempt: the idempotency
  key covers the customer, meter, and period, and Stripe rejects a reused
  key whose parameters changed.

  Returns `{:ok, :already_reported}` when Stripe rejects the event as a
  duplicate, so the caller treats it as delivered instead of retrying.
  """
  def report_meter_event(
        customer_id,
        event_name,
        value,
        %DateTime{} = period_start,
        %DateTime{} = period_end,
        %DateTime{} = reported_at
      )
      when is_binary(customer_id) and is_binary(event_name) and is_integer(value) and value >= 0 do
    identifier =
      "#{customer_id}-#{event_name}-#{DateTime.to_unix(period_start)}-#{DateTime.to_unix(period_end)}"

    []
    |> Stripe.Request.new_request(%{"Idempotency-Key" => identifier})
    |> Stripe.Request.put_endpoint(Stripe.OpenApi.Path.replace_path_params("/v1/billing/meter_events", [], []))
    |> Stripe.Request.put_params(%{
      event_name: event_name,
      identifier: identifier,
      timestamp: DateTime.to_unix(usage_timestamp(period_start, period_end, reported_at)),
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
  #
  # Also never stamp in the future: Stripe rejects a future-dated meter
  # event outright. A window can still be open when it is reported —
  # reporting the current day rather than waiting for the nightly run, or
  # backfilling a period that has not closed — and `period_end - 1s` is
  # then still ahead of `reported_at`. Clamping keeps the event inside the
  # same service period, so attribution is unchanged.
  #
  # `reported_at` has to be stable across retries rather than read from
  # the clock here. The idempotency key covers the customer, meter, and
  # period, so two attempts that sent different timestamps under it would
  # be rejected as reusing a key with changed parameters. The caller
  # passes an instant fixed when the work was first enqueued.
  defp usage_timestamp(period_start, period_end, reported_at) do
    candidate = DateTime.add(period_end, -1, :second)
    timestamp = if DateTime.after?(candidate, reported_at), do: reported_at, else: candidate

    if DateTime.before?(timestamp, period_start), do: period_start, else: timestamp
  end

  def update_plan(%{plan: plan, account: %Account{} = account, success_url: success_url}) do
    customer_id = account.customer_id

    current_subscription = get_current_active_subscription(account)

    subscription_items = get_subscription_items(to_string(plan), account)

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

      {:ok, _} =
        Stripe.Subscription.update(current_subscription.subscription_id, %{
          items: reconcile_subscription_items(stripe_subscription, subscription_items)
        })

      :ok
    end
  end

  # A plan change replaces the plan's own items wholesale, but runner items
  # must survive it untouched. In Stripe's classic billing mode, deleting a
  # metered item stops the eventual invoice from reflecting the usage that
  # accrued on it, and a freshly added metered item only captures usage from
  # the moment it was added. Since runner Prices are plan-independent and
  # usually unchanged by the plan change, deleting and re-adding them would
  # silently discard the runner usage already accrued this cycle.
  #
  # So: keep every existing item whose Price is a configured runner Price,
  # delete the rest, and add only the runner Prices that aren't on the
  # subscription yet. Runner items keep their Stripe item IDs and their
  # accrued usage across the change.
  defp reconcile_subscription_items(stripe_subscription, subscription_items) do
    runner_price_ids = configured_runner_price_ids()

    {retained, replaced} =
      Enum.split_with(stripe_subscription.items.data, fn item ->
        MapSet.member?(runner_price_ids, subscription_item_price_id(item))
      end)

    retained_price_ids = MapSet.new(retained, &subscription_item_price_id/1)

    deletions = Enum.map(replaced, &%{id: &1.id, deleted: true})

    additions =
      Enum.reject(subscription_items, fn item ->
        MapSet.member?(retained_price_ids, Map.get(item, :price))
      end)

    deletions ++ additions
  end

  defp subscription_item_price_id(%{price: %{id: price_id}}) when is_binary(price_id), do: price_id
  defp subscription_item_price_id(_item), do: nil

  defp configured_runner_price_ids do
    (Tuist.Environment.stripe_prices() || %{})
    |> Map.get("runners", %{})
    |> Map.values()
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> MapSet.new()
  end

  defp get_subscription_items(plan, account) do
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

    usage_prices ++ runner_subscription_items(available_prices, account) ++ flat_prices
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

    subscription_items = enterprise_subscription_items(Map.get(params, :cadence, "monthly"), account)
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

        {:ok, sub} =
          Stripe.Subscription.update(current_subscription.subscription_id, %{
            items: reconcile_subscription_items(current_stripe_sub, subscription_items),
            collection_method: "send_invoice",
            days_until_due: Map.get(params, :days_until_due, 30)
          })

        sub
      end

    on_subscription_change(stripe_sub)
    {:ok, stripe_sub}
  end

  defp enterprise_subscription_items(cadence, account) do
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

    usage_prices ++ runner_subscription_items(available_prices, account) ++ flat_prices
  end

  # An account on a runner trial carries no runner item, which is what
  # makes its runner usage unbillable: usage is still metered and still
  # reported gross, but there is nothing on the subscription for Stripe
  # to invoice it against. See `Tuist.Runners.Trials`.
  defp runner_subscription_items(available_prices, account) do
    if Trials.on_trial?(account) do
      []
    else
      configured_runner_prices(available_prices)
    end
  end

  defp configured_runner_prices(available_prices) do
    available_prices
    |> Map.get("runners", %{})
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.flat_map(fn
      {_meter_event_name, price_id} when is_binary(price_id) and price_id != "" -> [%{price: price_id}]
      _ -> []
    end)
  end

  @doc """
  Reconciles `account`'s live subscription so its runner items match its
  trial state: an account on a runner trial carries none, and one off
  trial carries every configured runner Price.

  Called when a trial starts or ends. Idempotent, and a no-op for an
  account with no active subscription — that account picks the items up
  from `get_subscription_items/2` whenever it next gets one.

  Ending a trial mid-period may make that period's earlier usage
  billable, depending on how Stripe attributes meter events recorded
  before the item existed. Until that is confirmed, prefer ending a
  trial at a period boundary.
  """
  def sync_runner_subscription_items(%Account{} = account) do
    case get_current_active_subscription(account) do
      %Subscription{subscription_id: subscription_id} when is_binary(subscription_id) ->
        with {:ok, stripe_subscription} <- Stripe.Subscription.retrieve(subscription_id) do
          apply_runner_item_changes(subscription_id, stripe_subscription, account)
        end

      _ ->
        {:ok, :no_subscription}
    end
  end

  defp apply_runner_item_changes(subscription_id, stripe_subscription, account) do
    runner_price_ids = configured_runner_price_ids()

    present =
      Enum.filter(stripe_subscription.items.data, &MapSet.member?(runner_price_ids, subscription_item_price_id(&1)))

    changes =
      if Trials.on_trial?(account) do
        Enum.map(present, &%{id: &1.id, deleted: true})
      else
        present_price_ids = MapSet.new(present, &subscription_item_price_id/1)

        (Tuist.Environment.stripe_prices() || %{})
        |> configured_runner_prices()
        |> Enum.reject(&MapSet.member?(present_price_ids, &1.price))
      end

    case changes do
      [] -> {:ok, :unchanged}
      changes -> Stripe.Subscription.update(subscription_id, %{items: changes})
    end
  end

  @doc """
  The account's current billing period as `{start, end}`, or `nil` when
  it has no active subscription or Stripe cannot be reached.

  Callers that need a window to attribute usage to should prefer this
  over the calendar month whenever it is available: Stripe resets
  tiered allowances on the subscription cycle, so a customer whose cycle
  does not start on the first would otherwise be shown a free tier that
  refreshes on a different day from the one they are billed against.

  Returns `nil` rather than raising, because a usage page that cannot
  reach Stripe should fall back to the calendar month rather than fail.
  """
  def current_billing_period(%Account{} = account) do
    with %Subscription{subscription_id: subscription_id} when is_binary(subscription_id) <-
           get_current_active_subscription(account),
         {:ok, stripe_subscription} <- Stripe.Subscription.retrieve(subscription_id),
         period_start when is_integer(period_start) <- Map.get(stripe_subscription, :current_period_start),
         period_end when is_integer(period_end) <- Map.get(stripe_subscription, :current_period_end) do
      {DateTime.from_unix!(period_start), DateTime.from_unix!(period_end)}
    else
      _ -> nil
    end
  end

  @doc """
  The `count` most recent billing periods, newest first, as
  `{start, end}` datetimes.

  Derived by stepping the current period back a month at a time rather
  than read from Stripe's invoice history: the anchor day is what makes
  a period, and stepping it reproduces the same bounds without a call
  per period. Accounts with no subscription get calendar months, which
  is the window their allowance follows.
  """
  def recent_billing_periods(%Account{} = account, count) when is_integer(count) and count > 0 do
    {period_start, period_end} = current_billing_period(account) || calendar_month(DateTime.utc_now())

    Enum.map(0..(count - 1), fn months_back ->
      {Timex.shift(period_start, months: -months_back), Timex.shift(period_end, months: -months_back)}
    end)
  end

  defp calendar_month(%DateTime{} = now) do
    period_start = %{now | day: 1, hour: 0, minute: 0, second: 0, microsecond: {0, 6}}

    {period_start, Timex.shift(period_start, months: 1)}
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
  Returns the effective plan for an account.

  Accounts without an active or trialing subscription use the Air plan.
  """
  def effective_plan(%Account{subscriptions: subscriptions}) when is_list(subscriptions) do
    subscriptions
    |> Enum.filter(&(&1.status in ["active", "trialing"]))
    |> case do
      [] -> :air
      active -> active |> latest_subscription() |> Map.fetch!(:plan)
    end
  end

  def effective_plan(%Account{} = account) do
    case get_current_active_subscription(account) do
      %{plan: plan} when is_atom(plan) -> plan
      _ -> :air
    end
  end

  @doc """
  Whether the account has exhausted the free tier and must upgrade before it
  can reach the cache again.

  Only Air accounts are gated. An account whose paid subscription lapsed
  resolves to Air, so it is gated on the same terms as one that never
  subscribed.
  """
  def cache_access_blocked?(%Account{} = account) do
    effective_plan(account) == :air and
      over_free_tier?(account.current_month_remote_cache_hits_count)
  end

  @doc """
  The ids of the given accounts whose free tier is exhausted.

  Only accounts already past the threshold need their plan resolved, and those
  are resolved in one query rather than one apiece, so the cache authorization
  paths do not scale a query per account the subject can reach.
  """
  def cache_blocked_account_ids(accounts) do
    candidates =
      accounts
      |> Enum.uniq_by(& &1.id)
      |> Enum.filter(&over_free_tier?(&1.current_month_remote_cache_hits_count))

    case candidates do
      [] ->
        MapSet.new()

      candidates ->
        plans = latest_active_plans(Enum.map(candidates, & &1.id))

        candidates
        |> Enum.filter(&(Map.get(plans, &1.id, :air) == :air))
        |> MapSet.new(& &1.id)
    end
  end

  # Ordered rather than compared in memory: `Enum.group_by/3` keeps the order it
  # is given within each group, and comparing `inserted_at` structs by term
  # order is not chronological.
  defp latest_active_plans(account_ids) do
    from(s in Subscription,
      where: s.account_id in ^account_ids,
      where: s.status in ["active", "trialing"],
      order_by: [desc: s.inserted_at, desc: s.id],
      select: {s.account_id, s.plan}
    )
    |> Repo.all()
    |> Enum.group_by(fn {account_id, _plan} -> account_id end, fn {_account_id, plan} -> plan end)
    |> Map.new(fn {account_id, [latest | _]} -> {account_id, latest} end)
  end

  # Elixir orders atoms above numbers, so a nil counter would compare as being
  # over the threshold and deny the account.
  defp over_free_tier?(nil), do: false

  defp over_free_tier?(count) do
    count >= get_payment_thresholds()[:remote_cache_hits]
  end

  defp latest_subscription([subscription | subscriptions]) do
    Enum.reduce(subscriptions, subscription, fn candidate, latest ->
      case NaiveDateTime.compare(candidate.inserted_at, latest.inserted_at) do
        :gt -> candidate
        :lt -> latest
        :eq -> if candidate.id > latest.id, do: candidate, else: latest
      end
    end)
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
