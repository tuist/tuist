defmodule Tuist.Billing.Invoices do
  @moduledoc """
  Reading Stripe invoice lines in full.

  An invoice's `lines` are a paginated list, and both the webhook
  payload and a plain retrieve carry only the first handful. Anything
  deciding on the basis of what is *on* an invoice has to page the
  dedicated lines endpoint, or it makes that decision from a truncated
  view of a busy month's bill: a prepaid line sitting eleventh on a
  monthly invoice would simply not be seen.
  """

  @page_limit 100
  # A hard stop so a pagination bug cannot spin. At 100 lines a page
  # this covers any invoice we could plausibly issue.
  @max_pages 20

  @doc """
  Every line on `invoice_id`, oldest page first.
  """
  def list_lines(invoice_id) when is_binary(invoice_id) do
    fetch_page(invoice_id, nil, [], @max_pages)
  end

  defp fetch_page(_invoice_id, _starting_after, acc, 0), do: {:ok, acc}

  defp fetch_page(invoice_id, starting_after, acc, pages_left) do
    params =
      case starting_after do
        nil -> %{limit: @page_limit}
        id -> %{limit: @page_limit, starting_after: id}
      end

    case get("/v1/invoices/#{invoice_id}/lines", params) do
      {:ok, %{data: data} = page} when is_list(data) ->
        acc = acc ++ data

        if Map.get(page, :has_more) == true and data != [] do
          fetch_page(invoice_id, List.last(data).id, acc, pages_left - 1)
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
end
