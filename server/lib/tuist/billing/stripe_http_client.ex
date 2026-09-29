defmodule Tuist.Billing.StripeHTTPClient do
  @moduledoc """
  The HTTP module Stripity Stripe sends its requests through.

  Hackney 4 can hand out a pooled connection that closes on its idle
  timeout in the same instant, and the request that reaches it fails
  with `{:error, :invalid_state}` without anything being sent. A second
  attempt checks out a live connection. Stripity Stripe's own retries
  don't cover that reason, and every other error is returned as is.
  """

  def request(method, url, headers, body, options) do
    case :hackney.request(method, url, headers, body, options) do
      {:error, :invalid_state} -> :hackney.request(method, url, headers, body, options)
      result -> result
    end
  end
end
