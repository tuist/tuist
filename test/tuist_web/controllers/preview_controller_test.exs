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

  test "sets the download url", %{conn: conn} do
    # Given
    Tuist.GitHub.Releases
    |> stub(:get_latest_app_release, fn ->
      %{
        published_at: Timex.format!(Timex.now(), "{ISO:Extended}"),
        name: "v2.0.0",
        html_url: "https://github.com/release",
        assets: [
          %{
            name: "tuist.zip",
            browser_download_url:
              "https://github.com/tuist/tuist/releases/download/app@0.1.0/app.dmg"
          }
        ]
      }
    end)

    # When
    conn =
      conn
      |> get(~p"/tuist/ios_app_with_frameworks/previews/01911326-4444-771b-8dfa-7d1fc5082eb9")

    # Then
    assert html_response(conn, 200) =~
             "Don't have the Tuist app installed? <a style=\"display: inline;\" href=\"https://github.com/tuist/tuist/releases/download/app@0.1.0/app.dmg\">Click here to download it.</a>"
  end
end
