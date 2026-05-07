defmodule CacheWeb.Plugs.BillingPlug do
  @moduledoc """
  Plug that blocks module cache requests when a free-tier account has
  surpassed the monthly thresholds.

  Reads the `hit_limit_surpassed` flag stashed on the connection by
  `CacheWeb.Plugs.AuthPlug` and rejects the request with `402 Payment Required`
  when it is `true`.

  When the flag is `nil` (e.g. JWT-only authorization that does not carry
  billing info) the request is let through.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(%Plug.Conn{assigns: %{hit_limit_surpassed: true}} = conn, _opts) do
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
