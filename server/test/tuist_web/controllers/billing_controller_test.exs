defmodule TuistWeb.BillingControllerTest do
  use TuistTestSupport.Cases.ConnCase
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Billing
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Errors.UnauthorizedError

  describe "upgrade" do
    test "creates the customer and redirects to Stripe when user has permission and billing returns an external redirect request",
         %{conn: conn} do
      %{account: account} =
        user =
        AccountsFixtures.user_fixture(
          email: "tuist@tuist.dev",
          customer_id: nil,
          preload: [:account]
        )

      success_url = url(~p"/#{account.name}/billing") <> "?new_plan=pro"
      account_with_customer_id = %{account | customer_id: UUIDv7.generate()}

      stub(Accounts, :create_customer_when_absent, fn _ ->
        account_with_customer_id
      end)

      expect(Billing, :update_plan, fn %{
                                         plan: :pro,
                                         account: ^account_with_customer_id,
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

    test "redirects to Stripe when user has permission and billing returns an external redirect request",
         %{conn: conn} do
      %{account: account} =
        user = AccountsFixtures.user_fixture(email: "tuist@tuist.dev", preload: [:account])

      success_url = url(~p"/#{account.name}/billing") <> "?new_plan=pro"

      expect(Billing, :update_plan, fn %{
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
        user = AccountsFixtures.user_fixture(email: "tuist@tuist.dev", preload: [:account])

      success_url = url(~p"/#{account.name}/billing") <> "?new_plan=pro"

      expect(Billing, :update_plan, fn %{
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
      user = AccountsFixtures.user_fixture(email: "tuist@tuist.dev")

      assert_raise UnauthorizedError, fn ->
        conn
        |> log_in_user(user)
        |> get("/#{organization_account.name}/billing/upgrade")
      end
    end
  end

  describe "manage" do
    test "creates the customer and redirects to Stripe when user has permission", %{conn: conn} do
      %{account: account} =
        user =
        AccountsFixtures.user_fixture(
          email: "tuist@tuist.dev",
          customer_id: nil,
          preload: [:account]
        )

      expect(Billing, :create_session, fn _ -> %{url: "https://stripe.com"} end)

      expect(Accounts, :create_customer_when_absent, fn ^account ->
        %{account | customer_id: UUIDv7.generate()}
      end)

      account_with_customer_id = %{account | customer_id: UUIDv7.generate()}

      stub(Accounts, :create_customer_when_absent, fn _ ->
        account_with_customer_id
      end)

      conn =
        conn
        |> log_in_user(user)
        |> get("/#{account.name}/billing/manage")

      assert redirected_to(conn) == "https://stripe.com"
    end

    test "redirects to Stripe when user has permission", %{conn: conn} do
      %{account: account} =
        user = AccountsFixtures.user_fixture(email: "tuist@tuist.dev", preload: [:account])

      expect(Billing, :create_session, fn _ -> %{url: "https://stripe.com"} end)

      expect(Accounts, :create_customer_when_absent, fn ^account ->
        %{account | customer_id: UUIDv7.generate()}
      end)

      conn =
        conn
        |> log_in_user(user)
        |> get("/#{account.name}/billing/manage")

      assert redirected_to(conn) == "https://stripe.com"
    end

    test "raises UnauthorizedError when user does not have permission", %{conn: conn} do
      organization = AccountsFixtures.organization_fixture()
      organization_account = Accounts.get_account_from_organization(organization)
      user = AccountsFixtures.user_fixture(email: "tuist@tuist.dev")

      assert_raise UnauthorizedError, fn ->
        conn
        |> log_in_user(user)
        |> get("/#{organization_account.name}/billing/manage")
      end
    end
  end
end
