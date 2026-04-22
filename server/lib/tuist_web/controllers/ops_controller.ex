defmodule TuistWeb.OpsController do
  @moduledoc """
  Controllers for ops-only endpoints that don't fit the LiveView model —
  currently just the Stripe billing portal handoff, which needs to run as a
  regular GET so the browser can open it in a new tab via `target="_blank"`.
  """
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Billing

  def stripe_session(conn, %{"id" => id}) do
    case Accounts.get_account_by_id(String.to_integer(id)) do
      {:ok, account} ->
        account = Accounts.create_customer_when_absent(account)
        session = Billing.create_session(account.customer_id)
        conn |> redirect(external: session.url) |> halt()

      {:error, :not_found} ->
        raise TuistWeb.Errors.NotFoundError, "Account not found."
    end
  end
end
