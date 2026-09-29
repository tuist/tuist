defmodule Tuist.Billing.StripeHTTPClient do
  @moduledoc """
  The HTTP module Stripity Stripe sends its requests through.

  Hackney 4 pools plain TCP connections to Stripe and upgrades one to TLS
  for each request. A pooled connection can close after the pool checked
  it was alive but before the caller uses it, and the call then fails
  with `{:error, :invalid_state}` without anything being sent. A second
  attempt gets another connection. Stripity Stripe's own retries don't
  cover that reason, and every other result is returned as is.
  """

  def request(method, url, headers, body, options) do
    case :hackney.request(method, url, headers, body, options) do
      {:error, :invalid_state} -> :hackney.request(method, url, headers, body, options)
      result -> result
    end
  end
end
