defmodule TuistCloudWeb.BillingController do
  @moduledoc """
  Controller for managing billing.
  """

  use TuistCloudWeb, :controller
  alias TuistCloud.Accounts
  alias TuistCloud.Authorization
  alias TuistCloud.Billing
  alias TuistCloudWeb.Authentication

  def manage(conn, %{"account_handle" => account_handle}) do
    account = Accounts.get_account_by_handle(account_handle)
    user = Authentication.current_user(conn)

    if Authorization.can(user, :update, account, :billing) do
      session = Billing.create_session(account.customer_id)
      redirect(conn, external: session.url) |> halt()
    else
      raise TuistCloudWeb.Errors.UnauthorizedError,
            "You don't have permission to access this account."
    end
  end
end
