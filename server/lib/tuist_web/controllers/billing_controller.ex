defmodule TuistWeb.BillingController do
  @moduledoc """
  Controller for managing billing.
  """

  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.Billing
  alias TuistWeb.Authentication

  plug :assign_billing_account
  plug :authorize

  def manage(%{assigns: %{billing_account: billing_account}} = conn, _params) do
    billing_account = Accounts.create_customer_when_absent(billing_account)
    session = Billing.create_session(billing_account.customer_id)
    conn |> redirect(external: session.url) |> halt()
  end

  def upgrade(%{assigns: %{billing_account: billing_account}} = conn, _params) do
    billing_account = Accounts.create_customer_when_absent(billing_account)

    case Billing.update_plan(%{
           plan: :pro,
           account: billing_account,
           success_url: url(~p"/#{billing_account.name}/billing") <> "?new_plan=pro"
         }) do
      # It requires redirecting to Stripe
      {:ok, {:external_redirect, session_url}} ->
        conn |> redirect(external: session_url) |> halt()

      :ok ->
        conn |> redirect(to: ~p"/#{billing_account.name}/billing") |> halt()
    end
  end

  def assign_billing_account(%{params: %{"account_handle" => account_handle}} = conn, _opts) do
    assign(conn, :billing_account, Accounts.get_account_by_handle(account_handle))
  end

  def authorize(%{assigns: %{billing_account: billing_account}} = conn, _opts) do
    if Authorization.authorize(
         :billing_update,
         Authentication.current_user(conn),
         billing_account
       ) == :ok do
      conn
    else
      raise TuistWeb.Errors.UnauthorizedError,
            "You don't have permission to access this account."
    end
  end
end
