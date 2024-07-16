defmodule TuistWeb.BillingControllerTest do
  use TuistWeb.ConnCase

  alias Tuist.Billing
  alias Tuist.AccountsFixtures
  alias Tuist.Accounts
  use Mimic

  test "redirects to Stripe when user has permission", %{conn: conn} do
    %{account: account} =
      user = AccountsFixtures.user_fixture(email: "tuist@tuist.io", preloads: [:account])

    Billing
    |> expect(:create_session, fn _ -> %{url: "https://stripe.com"} end)

    conn =
      conn
      |> log_in_user(user)
      |> get("/#{account.name}/billing/manage")

    assert redirected_to(conn) == "https://stripe.com"
  end

  test "raises UnauthorizedError when user does not have permission", %{conn: conn} do
    organization = AccountsFixtures.organization_fixture()
    organization_account = Accounts.get_account_from_organization(organization)
    user = AccountsFixtures.user_fixture(email: "tuist@tuist.io")

    assert_raise TuistWeb.Errors.UnauthorizedError, fn ->
      conn
      |> log_in_user(user)
      |> get("/#{organization_account.name}/billing/manage")
    end
  end
end
