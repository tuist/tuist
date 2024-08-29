defmodule TuistWeb.PreviewControllerTest do
  use TuistWeb.ConnCase, async: true
  use Mimic

  alias Tuist.AccountsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    conn =
      conn
      |> log_in_user(user)

    %{conn: conn, user: user}
  end

  test "renders a download button", %{conn: conn} do
    # When
    conn =
      conn
      |> get(~p"/tuist/ios_app_with_frameworks/previews/01911326-4444-771b-8dfa-7d1fc5082eb9")

    # Then
    assert html_response(conn, 200) =~
             "Don't have the Tuist app installed? <a style=\"display: inline;\" href=\"/download\">Click here to download it.</a>"
  end
end
