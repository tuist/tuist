defmodule Tuist.DownloadControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.GitHub.Releases

  test "redirects to the browser_download_url", %{conn: conn} do
    # Given
    stub(Releases, :get_latest_app_release, fn ->
      %{
        published_at: Timex.format!(DateTime.utc_now(), "{ISO:Extended}"),
        name: "v2.0.0",
        html_url: "https://github.com/release",
        assets: [
          %{
            name: "tuist.zip",
            browser_download_url: "https://github.com/tuist/tuist/releases/download/app@0.1.0/app.dmg"
          }
        ]
      }
    end)

    # When
    conn = get(conn, ~p"/download")

    # Then
    assert redirected_to(conn) ==
             "https://github.com/tuist/tuist/releases/download/app@0.1.0/app.dmg"
  end

  test "raises not found error when latest_app_release is nil", %{conn: conn} do
    # Given
    stub(Releases, :get_latest_app_release, fn -> nil end)

    # When / Then
    assert_raise TuistWeb.Errors.NotFoundError, fn ->
      get(conn, "/download")
    end
  end
end
