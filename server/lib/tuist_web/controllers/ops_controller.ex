defmodule TuistWeb.OpsController do
  @moduledoc """
  Controllers for ops-only endpoints that don't fit the LiveView model —
  currently just the Stripe dashboard handoff, which needs to run as a
  regular GET so the browser can open it in a new tab via `target="_blank"`.
  """
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Environment

  def stripe_customer(conn, %{"id" => id}) do
    case Accounts.get_account_by_id(String.to_integer(id)) do
      {:ok, account} ->
        account = Accounts.create_customer_when_absent(account)
        conn |> redirect(external: stripe_dashboard_customer_url(account.customer_id)) |> halt()

      {:error, :not_found} ->
        raise TuistWeb.Errors.NotFoundError, "Account not found."
    end
  end

  # Pick the live vs test mode dashboard based on the Stripe secret key in
  # use. Avoids dropping ops into the wrong mode and seeing "no customer".
  defp stripe_dashboard_customer_url(customer_id) do
    "https://dashboard.stripe.com#{dashboard_mode_segment()}/customers/#{customer_id}"
  end

  defp dashboard_mode_segment do
    case Environment.stripe_api_key() do
      "sk_test_" <> _ -> "/test"
      _ -> ""
    end
  end
end
