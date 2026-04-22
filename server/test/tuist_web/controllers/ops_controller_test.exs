defmodule TuistWeb.OpsControllerTest do
  use TuistTestSupport.Cases.ConnCase
  use Mimic

  alias Tuist.Billing
  alias Tuist.Environment
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :verify_on_exit!

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    conn = log_in_user(conn, user)
    Mimic.stub(Environment, :ops_user_handles, fn -> [user.account.name] end)

    %{conn: conn, user: user}
  end

  test "GET /ops/accounts/:id/stripe-session redirects to the Stripe billing portal", %{
    conn: conn,
    user: user
  } do
    expect(Billing, :create_session, fn customer_id ->
      assert customer_id == user.account.customer_id
      %{url: "https://billing.stripe.test/session"}
    end)

    conn = get(conn, ~p"/ops/accounts/#{user.account.id}/stripe-session")

    assert redirected_to(conn, 302) == "https://billing.stripe.test/session"
  end
end
