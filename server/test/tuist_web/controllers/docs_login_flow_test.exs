defmodule TuistWeb.DocsLoginFlowTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias TuistWeb.RateLimit.Auth

  setup do
    stub(Auth, :hit, fn _ -> {:allow, 1000} end)
    %{user: user_fixture(preload: [:account])}
  end

  test "docs login flow returns user to the original docs page", %{conn: conn, user: user} do
    conn = get(conn, ~p"/docs/login?#{%{return_to: "/en/docs/guides"}}")
    assert redirected_to(conn) == ~p"/users/log_in?#{%{return_to: "/en/docs/guides"}}"
    assert get_session(conn, :user_return_to) == "/en/docs/guides"

    conn = Phoenix.ConnTest.recycle(conn)
    conn = get(conn, ~p"/users/log_in")
    assert conn.status == 200
    assert get_session(conn, :user_return_to) == "/en/docs/guides"

    conn = Phoenix.ConnTest.recycle(conn)

    conn =
      post(conn, ~p"/users/log_in", %{
        "user" => %{"email" => user.email, "password" => valid_user_password()}
      })

    assert redirected_to(conn) == "/en/docs/guides"
  end
end
