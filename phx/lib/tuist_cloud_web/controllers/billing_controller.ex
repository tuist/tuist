defmodule TuistCloudWeb.BillingController do
  @moduledoc """
  Controller for managing billing.
  """

  use TuistCloudWeb, :controller
  alias TuistCloud.Accounts
  alias TuistCloud.Authorization
  alias TuistCloud.Billing
  alias TuistCloudWeb.Authentication

  def billing_plan(conn, %{"account_name" => account_name}) do
    account = Accounts.get_account_by_handle(account_name)
    user = Authentication.authenticated_user(conn)

    if Authorization.can(user, :update, account, :billing) do
      session = Billing.create_session(customer: account.customer_id)
      redirect(conn, external: session.url)
    else
      raise TuistCloudWeb.Errors.UnauthorizedError,
            "You don't have permission to access this account."
    end
  end
end
