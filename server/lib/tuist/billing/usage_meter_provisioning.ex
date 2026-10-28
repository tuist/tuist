defmodule Tuist.Billing.UsageMeterProvisioning do
  @moduledoc """
  Creates the Stripe Meters and Prices that usage-based pricing bills on.

  Idempotent: a Meter is found by its event name and a Price by its lookup
  key, so a second run answers with what already exists instead of creating a
  duplicate. The tiers come from `Tuist.Billing.UsagePricing.meter_prices/0`,
  so a Price cannot be provisioned at a rate the dashboard does not quote, and
  a Price whose tiers no longer match them is replaced by a new one.

  Run it against test mode first. Live mode needs `live: true`, because the
  Prices it creates are what customers are charged on.
  """

  alias Tuist.Billing.UsagePricing
  alias Tuist.Environment

  @product_names %{
    "cache_egress_megabytes" => "Cache egress",
    "cache_requests" => "Cache requests",
    "passing_test_cases" => "Passing test cases"
  }

  @doc """
  Provisions every meter and answers with `%{event_name => price_id}`, ready
  to paste into `stripe.prices.usage_meters`.
  """
  def provision(opts \\ []) do
    with :ok <- check_mode(Keyword.get(opts, :live, false)) do
      Enum.reduce_while(UsagePricing.meter_prices(), {:ok, %{}}, fn meter, {:ok, price_ids} ->
        case provision_meter(meter) do
          {:ok, price_id} -> {:cont, {:ok, Map.put(price_ids, meter.event_name, price_id)}}
          {:error, reason} -> {:halt, {:error, {meter.event_name, reason}}}
        end
      end)
    end
  end

  @doc """
  Whether the configured key addresses test mode. A key that is missing
  altogether is neither, and provisioning refuses to guess.
  """
  def test_mode? do
    case Environment.stripe_api_key() do
      key when is_binary(key) and key != "" -> String.contains?(key, "_test_")
      _ -> nil
    end
  end

  defp check_mode(live?) do
    case {test_mode?(), live?} do
      {nil, _} -> {:error, :stripe_api_key_not_configured}
      {true, _} -> :ok
      {false, true} -> :ok
      {false, false} -> {:error, :refusing_live_mode_without_opt_in}
    end
  end

  defp provision_meter(%{event_name: event_name} = meter) do
    with {:ok, meter_id} <- find_or_create_meter(event_name) do
      find_or_create_price(meter, meter_id)
    end
  end

  defp find_or_create_meter(event_name) do
    with {:ok, %{data: meters}} <- request(:get, "/v1/billing/meters", %{status: "active", limit: 100}) do
      case Enum.find(meters, &(&1.event_name == event_name)) do
        %{id: id} -> {:ok, id}
        nil -> create_meter(event_name)
      end
    end
  end

  # `value` and `stripe_customer_id` are the payload keys
  # `Billing.report_meter_event/6` posts under, and `sum` is what makes a
  # period's events add up rather than the last one winning.
  defp create_meter(event_name) do
    with {:ok, %{id: id}} <-
           request(:post, "/v1/billing/meters", %{
             display_name: @product_names[event_name],
             event_name: event_name,
             default_aggregation: %{formula: "sum"},
             customer_mapping: %{type: "by_id", event_payload_key: "stripe_customer_id"},
             value_settings: %{event_payload_key: "value"}
           }) do
      {:ok, id}
    end
  end

  # Stripe Prices are immutable, so a rate or an allowance change is a new
  # Price on the same Product. It takes the lookup key over from the old one,
  # which stays active for the subscriptions that still carry it.
  defp find_or_create_price(%{event_name: event_name} = meter, meter_id) do
    lookup_key = lookup_key(event_name)

    with {:ok, %{data: prices}} <-
           request(:get, "/v1/prices", %{lookup_keys: [lookup_key], limit: 1, expand: ["data.tiers"]}) do
      case prices do
        [%{id: id} = price | _] ->
          if tiers_match?(price, meter),
            do: {:ok, id},
            else: create_price(meter, meter_id, lookup_key, %{product: price.product})

        [] ->
          create_price(meter, meter_id, lookup_key, %{product_data: %{name: "Tuist #{@product_names[event_name]}"}})
      end
    end
  end

  defp tiers_match?(%{tiers: [%{up_to: included, unit_amount: 0}, %{up_to: nil, unit_amount_decimal: rate}]}, meter)
       when not is_nil(rate) do
    included == meter.included and Decimal.equal?(Decimal.new(rate), Decimal.new(unit_amount_decimal(meter)))
  end

  defp tiers_match?(_price, _meter), do: false

  # Graduated tiers, so the allowance is charged at nothing and only what
  # goes past it is charged at the rate. `unit_amount_decimal` carries the
  # fraction of a cent a single unit costs, which is what a per-GB or
  # per-million rate comes to once the meter reports megabytes or test cases.
  defp create_price(meter, meter_id, lookup_key, product) do
    params =
      Map.merge(
        %{
          currency: "usd",
          lookup_key: lookup_key,
          transfer_lookup_key: true,
          billing_scheme: "tiered",
          tiers_mode: "graduated",
          tiers: [
            %{up_to: meter.included, unit_amount: 0},
            %{up_to: "inf", unit_amount_decimal: unit_amount_decimal(meter)}
          ],
          recurring: %{interval: "month", usage_type: "metered", meter: meter_id}
        },
        product
      )

    with {:ok, %{id: id}} <- request(:post, "/v1/prices", params) do
      {:ok, id}
    end
  end

  defp unit_amount_decimal(%{cents: cents, per_units: per_units}) do
    cents
    |> Decimal.new()
    |> Decimal.div(Decimal.new(per_units))
    |> Decimal.to_string(:normal)
  end

  defp lookup_key(event_name), do: "tuist_#{event_name}"

  defp request(method, endpoint, params) do
    []
    |> Stripe.Request.new_request()
    |> Stripe.Request.put_endpoint(endpoint)
    |> Stripe.Request.put_params(params)
    |> Stripe.Request.put_method(method)
    |> Stripe.Request.make_request()
  end
end
