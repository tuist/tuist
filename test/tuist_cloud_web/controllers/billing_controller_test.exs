defmodule TuistCloudWeb.BillingControllerTest do
  use TuistCloudWeb.ConnCase

  alias TuistCloud.Billing
  alias TuistCloud.AccountsFixtures
  alias TuistCloud.Accounts
  use Mimic

  test "redirects to Stripe when user has permission", %{conn: conn} do
    user = AccountsFixtures.user_fixture(email: "tuist@tuist.io")
    account = Accounts.get_account_from_user(user)

    Billing
    |> expect(:create_session, fn _ -> %{url: "https://stripe.com"} end)

    conn =
      conn
      |> log_in_user(user)
      |> get("/#{account.name}/billing")

    assert redirected_to(conn) == "https://stripe.com"
  end

  test "raises UnauthorizedError when user does not have permission", %{conn: conn} do
    organization = AccountsFixtures.organization_fixture()
    organization_account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture(email: "tuist@tuist.io")

    assert_raise TuistCloudWeb.Errors.UnauthorizedError, fn ->
      conn
      |> log_in_user(user)
      |> get("/#{organization_account.name}/billing")
    end
  end
end
