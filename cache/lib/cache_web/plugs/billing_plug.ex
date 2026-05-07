defmodule CacheWeb.Plugs.BillingPlug do
  @moduledoc """
  Plug that blocks module cache requests when a free-tier account has
  surpassed the monthly thresholds.

  Reads the billing snapshot stashed on `conn.assigns[:account_billing]` by
  `CacheWeb.Plugs.AuthPlug` and rejects the request with `402 Payment Required`
  for air-plan accounts over the threshold.

  When the billing snapshot is `nil` (e.g. JWT-only authorization that does not
  carry billing info) the request is let through. Paid plans are not enforced
  here; lapsed paid subscriptions surface as `:air` from
  `Tuist.Billing.account_billing_status/1` and fall back to the same free-tier
  check.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(%Plug.Conn{assigns: %{account_billing: %{plan: :air, thresholds_surpassed: true}}} = conn, _opts) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(402, JSON.encode!(%{message: rejection_message()}))
    |> halt()
  end

  def call(conn, _opts), do: conn

  defp rejection_message do
    "This account has reached the free tier limits. Upgrade to the 'Tuist Pro' plan to continue using the cache."
  end
end
