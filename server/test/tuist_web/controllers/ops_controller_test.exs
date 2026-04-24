defmodule TuistWeb.OpsControllerTest do
  use TuistTestSupport.Cases.ConnCase
  use Mimic

  alias Tuist.Environment
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :verify_on_exit!

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    conn = log_in_user(conn, user)
    Mimic.stub(Environment, :ops_user_handles, fn -> [user.account.name] end)

    %{conn: conn, user: user}
  end

  test "GET /ops/accounts/:id/stripe-customer redirects to the live Stripe dashboard", %{
    conn: conn,
    user: user
  } do
    stub(Environment, :stripe_api_key, fn -> "sk_live_abc123" end)

    conn = get(conn, ~p"/ops/accounts/#{user.account.id}/stripe-customer")

    assert redirected_to(conn, 302) ==
             "https://dashboard.stripe.com/customers/#{user.account.customer_id}"
  end

  test "uses the /test dashboard segment when a test-mode Stripe key is configured", %{
    conn: conn,
    user: user
  } do
    stub(Environment, :stripe_api_key, fn -> "sk_test_abc123" end)

    conn = get(conn, ~p"/ops/accounts/#{user.account.id}/stripe-customer")

    assert redirected_to(conn, 302) ==
             "https://dashboard.stripe.com/test/customers/#{user.account.customer_id}"
  end
end
