defmodule TuistWeb.BillingControllerTest do
  use TuistTestSupport.Cases.ConnCase

  alias Tuist.Billing
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias Tuist.Accounts
  use Mimic

  describe "upgrade" do
    test "redirects to Stripe when user has permission and billing returns an external redirect request",
         %{conn: conn} do
      %{account: account} =
        user = AccountsFixtures.user_fixture(email: "tuist@tuist.io", preload: [:account])

      success_url = url(~p"/#{account.name}/billing") <> "?new_plan=pro"

      Billing
      |> expect(:update_plan, fn %{
                                   plan: :pro,
                                   account: ^account,
                                   success_url: ^success_url
                                 } ->
        {:ok, {:external_redirect, "https://stripe.com"}}
      end)

      conn =
        conn
        |> log_in_user(user)
        |> get("/#{account.name}/billing/upgrade")

      assert redirected_to(conn) == "https://stripe.com"
    end

    test "redirects to Stripe when user has permission and billing returns a success", %{
      conn: conn
    } do
      %{account: account} =
        user = AccountsFixtures.user_fixture(email: "tuist@tuist.io", preload: [:account])

      success_url = url(~p"/#{account.name}/billing") <> "?new_plan=pro"

      Billing
      |> expect(:update_plan, fn %{
                                   plan: :pro,
                                   account: ^account,
                                   success_url: ^success_url
                                 } ->
        :ok
      end)

      conn =
        conn
        |> log_in_user(user)
        |> get("/#{account.name}/billing/upgrade")

      assert redirected_to(conn) == ~p"/#{account.name}/billing"
    end

    test "raises UnauthorizedError when user does not have permission", %{conn: conn} do
      organization = AccountsFixtures.organization_fixture()
      organization_account = Accounts.get_account_from_organization(organization)
      user = AccountsFixtures.user_fixture(email: "tuist@tuist.io")

      assert_raise TuistWeb.Errors.UnauthorizedError, fn ->
        conn
        |> log_in_user(user)
        |> get("/#{organization_account.name}/billing/upgrade")
      end
    end
  end

  describe "manage" do
    test "redirects to Stripe when user has permission", %{conn: conn} do
      %{account: account} =
        user = AccountsFixtures.user_fixture(email: "tuist@tuist.io", preload: [:account])

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
end
