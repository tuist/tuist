defmodule TuistCloudWeb.BillingController do
  @moduledoc """
  Controller for managing billing.
  """

  use TuistCloudWeb, :controller
  alias TuistCloud.Accounts
  alias TuistCloud.Authorization
  alias TuistCloud.Billing

  def billing_plan(conn, %{"account_name" => account_name}) do
    account = Accounts.get_account_by_handle(account_name)

    if Authorization.can(current_user(), :update, account, :billing) do
      session = Billing.create_session(customer: account.customer_id)
      redirect(conn, external: session.url)
    else
      raise TuistCloudWeb.Errors.UnauthorizedError, "You don't have permission to access this account."
    end
  end

  def current_user do
    TuistCloud.Accounts.get_tuist_user()
  end
end
