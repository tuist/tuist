defmodule Tuist.Runners.PrepaidExpiry do
  @moduledoc """
  Closes the last prepaid usage period at the contractual cutoff.

  A Stripe credit grant is selected by invoice period, not job timestamp.
  Expiring it at midnight loses the final invoice; covering the normal next
  renewal also pays for post-term jobs. A scheduled anchor reset closes the
  final period at midnight, then releases the unchanged subscription after
  one monthly phase. The grant's four-day settlement grace cannot fund that
  next month's usage invoice. No replacement pool is scheduled.

  Only runner subscriptions with no other paid items are supported, plus the
  cache usage Prices when the pool also covers cache usage (`covers_cache:
  true`): changing
  another service's invoice date or payment terms would require a separate
  commercial decision. Existing schedules are never overwritten.
  """

  alias Tuist.Billing
  alias Tuist.Runners.Prepaid

  # Automatic tax is inherited from the imported schedule's defaults. Its
  # response also contains read-only fields that Stripe refuses on update.
  @phase_fields ~w(application_fee_percent billing_thresholds
                  collection_method coupon currency default_payment_method default_tax_rates
                  description invoice_settings items metadata on_behalf_of transfer_data)a

  def subscription(account) do
    case Billing.get_current_active_subscription(account) do
      %{subscription_id: id} ->
        # The installed generated Subscription struct predates billing_mode
        # and silently drops it. Read a version that exposes it and retain
        # the mode before conversion: flexible mode has different invoicing
        # semantics when resetting an anchor without prorations.
        with {:ok, raw} <-
               Stripe.API.request(%{}, :get, "/v1/subscriptions/#{id}", %{"Stripe-Version" => "2025-06-30.basil"}, []) do
          subscription =
            raw
            |> Stripe.Converter.convert_result()
            |> Map.put(:discounts, Map.get(raw, "discounts"))

          {:ok, Map.put(subscription, :billing_mode, get_in(raw, ["billing_mode", "type"]))}
        end

      _ ->
        {:error, :monthly_subscription_required}
    end
  end

  def validate(subscription, activation_id, opts \\ [])

  def validate(
        %{status: "active", cancel_at_period_end: false, cancel_at: nil, billing_mode: "classic"} = subscription,
        activation_id,
        opts
      ) do
    prepaid_prices = prepaid_prices(Keyword.get(opts, :covers_cache, false))

    supported_items? =
      is_nil(Map.get(subscription, :billing_thresholds)) and
        Enum.all?(subscription.items.data, &supported_item?(&1, prepaid_prices))

    cond do
      not supported_items? or not is_nil(Map.get(subscription, :discount)) or
          Map.get(subscription, :discounts, []) not in [nil, []] ->
        {:error, :runner_only_subscription_required}

      is_nil(subscription.schedule) ->
        :ok

      true ->
        with {:ok, schedule} <- Stripe.SubscriptionSchedule.retrieve(object_id(subscription.schedule)) do
          if metadata(schedule)["tuist_prepaid_activation_id"] == activation_id,
            do: :ok,
            else: {:error, :subscription_schedule_exists}
        end
    end
  end

  def validate(%{billing_mode: mode}, _activation_id, _opts) when mode != "classic",
    do: {:error, :classic_billing_required}

  def validate(_subscription, _activation_id, _opts), do: {:error, :active_subscription_required}

  defp prepaid_prices(covers_cache) do
    cache_prices =
      case covers_cache && Prepaid.cache_price_ids() do
        {:ok, ids} -> ids
        _none -> []
      end

    Map.values(Map.get(Tuist.Environment.stripe_prices() || %{}, "runners", %{})) ++ cache_prices
  end

  defp supported_item?(item, prepaid_prices) do
    price = item.price

    is_nil(Map.get(item, :billing_thresholds)) and price.recurring.interval == "month" and
      price.recurring.interval_count == 1 and
      (price.id in prepaid_prices or (price.recurring.usage_type == "licensed" and item.quantity == 0))
  end

  def schedule(account, activation_id, expires_on, opts \\ []) do
    cutoff = expires_on |> Date.add(1) |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    with {:ok, subscription} <- subscription(account),
         :ok <- validate(%{subscription | schedule: nil}, activation_id, opts),
         {:ok, schedule} <- get_or_create(subscription, activation_id),
         {:ok, schedule} <- set_boundary(schedule, activation_id, cutoff) do
      {:ok, schedule.id}
    end
  end

  defp get_or_create(%{schedule: nil, id: subscription_id}, activation_id) do
    Stripe.SubscriptionSchedule.create(
      %{from_subscription: subscription_id},
      headers: %{"Idempotency-Key" => "runner-pool-schedule-#{activation_id}"}
    )
  end

  defp get_or_create(%{schedule: schedule, id: subscription_id}, activation_id) do
    with {:ok, schedule} <- Stripe.SubscriptionSchedule.retrieve(object_id(schedule)) do
      if metadata(schedule)["tuist_prepaid_activation_id"] == activation_id do
        {:ok, schedule}
      else
        # Creating from a subscription cannot overwrite an attached schedule.
        # Only Stripe's cached response to OUR create key can prove ownership
        # after a crash between creation and tagging. Once that key expires,
        # fail safely for manual reconciliation rather than adopt by shape.
        case get_or_create(%{schedule: nil, id: subscription_id}, activation_id) do
          {:ok, %{id: id}} when id == schedule.id -> {:ok, schedule}
          {:ok, _} -> {:error, :subscription_schedule_exists}
          error -> error
        end
      end
    end
  end

  defp set_boundary(schedule, activation_id, cutoff) do
    cutoff_unix = DateTime.to_unix(cutoff)

    if Enum.any?(schedule.phases, fn phase ->
         phase.start_date == cutoff_unix and Map.get(phase, :billing_cycle_anchor) == "phase_start"
       end) do
      {:ok, schedule}
    else
      case schedule.phases do
        [phase] ->
          base =
            phase
            |> Map.take(@phase_fields)
            |> Map.reject(fn {_key, value} -> is_nil(value) end)
            |> Map.put(:items, Enum.map(phase.items, &item_params/1))
            |> Map.put(:default_tax_rates, Enum.map(Map.get(phase, :default_tax_rates) || [], &object_id/1))
            |> Map.put(:collection_method, "send_invoice")
            |> Map.put(:invoice_settings, Map.put(Map.get(phase, :invoice_settings) || %{}, :days_until_due, 30))
            |> Map.put(:proration_behavior, "none")

          # The imported schedule's defaults preserve the subscription's tax
          # and payment configuration. Only the explicit order terms change.
          Stripe.SubscriptionSchedule.update(
            schedule.id,
            %{
              end_behavior: "release",
              proration_behavior: "none",
              metadata: %{"tuist_prepaid_activation_id" => activation_id},
              phases: [
                Map.merge(base, %{start_date: phase.start_date, end_date: cutoff_unix}),
                Map.merge(base, %{
                  start_date: cutoff_unix,
                  end_date: cutoff |> DateTime.shift(month: 1) |> DateTime.to_unix(),
                  billing_cycle_anchor: "phase_start"
                })
              ]
            },
            headers: %{"Idempotency-Key" => "runner-pool-cutoff-#{activation_id}"}
          )

        _ ->
          {:error, :subscription_schedule_exists}
      end
    end
  end

  defp item_params(item) do
    item
    |> Map.take([:quantity, :billing_thresholds, :metadata])
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.put(:price, object_id(item.price))
    |> Map.put(:tax_rates, Enum.map(Map.get(item, :tax_rates) || [], &object_id/1))
  end

  defp metadata(schedule), do: Map.new(schedule.metadata || %{}, fn {key, value} -> {to_string(key), value} end)
  defp object_id(%{id: id}), do: id
  defp object_id(id), do: id
end
