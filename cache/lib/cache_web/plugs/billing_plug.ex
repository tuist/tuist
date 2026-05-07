defmodule CacheWeb.Plugs.BillingPlug do
  @moduledoc """
  Plug that enforces plan limits on cache requests.

  Reads the billing snapshot stashed on `conn.assigns[:account_billing]` by
  `CacheWeb.Plugs.AuthPlug` and rejects the request with `402 Payment Required`
  when the account has surpassed the free tier thresholds without a paid
  subscription, or when a paid plan is no longer active.

  When the billing snapshot is `nil` (e.g. JWT-only authorization that does not
  carry billing info), the request is let through. The server-side
  `TuistWeb.API.Authorization.BillingPlug` remains the authoritative gate for
  flows that hit the server.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(%Plug.Conn{assigns: %{account_billing: billing}} = conn, _opts) when is_map(billing) do
    case enforce(billing) do
      :ok -> conn
      {:reject, message} -> reject(conn, message)
    end
  end

  def call(conn, _opts), do: conn

  defp enforce(%{plan: :air, thresholds_surpassed: true}) do
    {:reject,
     "This account has reached the free tier limits. Upgrade to the 'Tuist Pro' plan to continue using the cache."}
  end

  defp enforce(%{plan: :air}), do: :ok

  defp enforce(%{plan: plan, subscription_active: false}) when plan in [:pro, :open_source, :enterprise] do
    {:reject, "The subscription for this account is not active. Update your billing details to continue."}
  end

  defp enforce(_billing), do: :ok

  defp reject(conn, message) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(402, JSON.encode!(%{message: message}))
    |> halt()
  end
end
