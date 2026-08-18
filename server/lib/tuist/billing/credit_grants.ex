defmodule Tuist.Billing.CreditGrants do
  @moduledoc """
  Stripe billing credit grants, and the balance left on them.

  A credit grant is a money-denominated balance Stripe draws down as
  metered usage is invoiced, restricted to the Prices the grant is
  scoped to. Tuist creates grants and reads what remains on them; the
  drawdown, the ordering between overlapping grants, and expiry are all
  Stripe's, so there is no second ledger here to keep in step with an
  invoice.

  `stripity_stripe` has no generated module for these endpoints, so the
  requests are hand-built the same way `Tuist.Billing.report_meter_event/5`
  builds meter events. Responses come back as plain maps with atom keys,
  since the converter only builds structs for object types it knows.

  Scoping is by explicit Price rather than by `price_type: "metered"`.
  A `metered` scope would let a grant pay for every metered Price on the
  account — remote cache hits and language-model tokens included — which
  is exactly what a runner-specific balance must not do.
  """

  @grants_endpoint "/v1/billing/credit_grants"
  @balance_summary_endpoint "/v1/billing/credit_balance_summary"

  @page_limit 100
  # A hard stop so a pagination bug cannot spin. Ten pages is far past
  # any realistic grant history for one customer.
  @max_pages 10

  @doc """
  Creates a credit grant for `customer_id`, scoped to `price_ids`.

  Required keys: `:customer_id`, `:amount_cents`, `:currency`,
  `:price_ids`. Optional: `:category` (`"paid"` for something the
  customer bought, `"promotional"` for something given away — Stripe
  reports the two separately), `:name`, `:expires_at`, `:priority`,
  `:metadata`, and `:idempotency_key`.

  A zero or negative amount is rejected rather than sent: Stripe would
  take it and the result would be a grant that can never pay for
  anything, which reads as a successful top-up in every listing.
  """
  def create(%{customer_id: customer_id, amount_cents: amount_cents, currency: currency, price_ids: price_ids} = attrs)
      when is_binary(customer_id) and is_integer(amount_cents) and amount_cents > 0 and is_binary(currency) and
             is_list(price_ids) and price_ids != [] do
    params =
      %{
        customer: customer_id,
        amount: %{
          type: "monetary",
          monetary: %{currency: String.downcase(currency), value: amount_cents}
        },
        applicability_config: %{scope: %{prices: Enum.map(price_ids, &%{id: &1})}},
        category: Map.get(attrs, :category, "paid")
      }
      |> put_present(:name, Map.get(attrs, :name))
      |> put_present(:priority, Map.get(attrs, :priority))
      |> put_present(:metadata, Map.get(attrs, :metadata))
      |> put_present(:expires_at, unix(Map.get(attrs, :expires_at)))

    headers =
      case Map.get(attrs, :idempotency_key) do
        key when is_binary(key) -> %{"Idempotency-Key" => key}
        _ -> %{}
      end

    []
    |> Stripe.Request.new_request(headers)
    |> Stripe.Request.put_endpoint(@grants_endpoint)
    |> Stripe.Request.put_params(params)
    |> Stripe.Request.put_method(:post)
    |> Stripe.Request.make_request()
  end

  @doc """
  Every credit grant on `customer_id`, oldest page first.

  Pages through the collection rather than reading the first 100, because
  callers use this to decide whether a grant already exists before
  creating another one, and a truncated list would answer "no" and grant
  the money twice.
  """
  def list_for_customer(customer_id) when is_binary(customer_id) do
    fetch_page(customer_id, nil, [], @max_pages)
  end

  @doc """
  Balance left on one grant, in the minor unit of the grant's currency.

  This is the drawn-down figure, which the grant object itself does not
  carry: `amount` on a grant is what was originally granted and never
  moves. Only Stripe knows what usage has consumed, so remaining balance
  is always a second call.
  """
  def available_balance_cents(customer_id, grant_id) when is_binary(customer_id) and is_binary(grant_id) do
    case get(@balance_summary_endpoint, %{
           customer: customer_id,
           filter: %{type: "credit_grant", credit_grant: grant_id}
         }) do
      {:ok, %{balances: balances}} when is_list(balances) ->
        {:ok, Enum.reduce(balances, 0, &(&2 + monetary_value(Map.get(&1, :available_balance))))}

      {:ok, _response} ->
        {:ok, 0}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_page(_customer_id, _starting_after, acc, 0), do: {:ok, acc}

  defp fetch_page(customer_id, starting_after, acc, pages_left) do
    params = put_present(%{customer: customer_id, limit: @page_limit}, :starting_after, starting_after)

    case get(@grants_endpoint, params) do
      {:ok, %{data: data} = page} when is_list(data) ->
        acc = acc ++ data

        if Map.get(page, :has_more) == true and data != [] do
          fetch_page(customer_id, List.last(data).id, acc, pages_left - 1)
        else
          {:ok, acc}
        end

      {:ok, _response} ->
        {:ok, acc}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get(endpoint, params) do
    []
    |> Stripe.Request.new_request()
    |> Stripe.Request.put_endpoint(endpoint)
    |> Stripe.Request.put_params(params)
    |> Stripe.Request.put_method(:get)
    |> Stripe.Request.make_request()
  end

  defp monetary_value(%{monetary: %{value: value}}) when is_integer(value), do: value
  defp monetary_value(_balance), do: 0

  defp unix(%DateTime{} = datetime), do: DateTime.to_unix(datetime)
  defp unix(_value), do: nil

  defp put_present(params, _key, nil), do: params
  defp put_present(params, _key, ""), do: params
  defp put_present(params, key, value), do: Map.put(params, key, value)
end
