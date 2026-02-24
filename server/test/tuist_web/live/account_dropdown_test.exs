defmodule TuistWeb.AccountDropdownTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Environment
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])

    Mimic.stub(Environment, :ops_user_handles, fn -> [] end)

    conn = log_in_user(conn, user)

    %{conn: conn, user: user}
  end

  test "does not show the Operations button for non-ops users", %{conn: conn, user: user} do
    # When
    {:ok, _lv, html} = live(conn, ~p"/#{user.account.name}/settings")

    # Then
    refute html =~ "/ops/qa"
    refute html =~ "Operations"
  end
end
