defmodule TuistWeb.Plugs.TimezonePlugTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias TuistWeb.Plugs.TimezonePlug

  defp call_with_cookie(value) do
    :get
    |> conn("/")
    |> put_req_cookie("user_timezone", value)
    |> fetch_cookies()
    |> init_test_session(%{})
    |> TimezonePlug.call([])
  end

  test "stores the timezone from the cookie in the session" do
    assert "America%2FSao_Paulo" |> call_with_cookie() |> get_session(:user_timezone) == "America/Sao_Paulo"
  end

  test "does not store a cookie value that is not a timezone" do
    refute "a" |> String.duplicate(4000) |> call_with_cookie() |> get_session(:user_timezone)
  end

  test "unchanged browser preferences do not emit a stale session cookie" do
    options = Plug.Session.init(store: :cookie, key: "session", signing_salt: "race-test")
    secret = String.duplicate("a", 64)

    for timezone <- [nil, "Europe/Madrid"] do
      seed =
        :get
        |> conn("/")
        |> Map.put(:secret_key_base, secret)
        |> Plug.Session.call(options)
        |> fetch_session()
        |> put_session(:locale, "en")
        |> put_session(:user_timezone, timezone)
        |> put_session(:user_return_to, "/old-preview")
        |> send_resp(200, "")

      stale =
        :get
        |> conn("/")
        |> Map.put(:secret_key_base, secret)
        |> put_req_cookie("session", seed.resp_cookies["session"].value)
        |> put_req_cookie("user_timezone", timezone || "")
        |> put_req_header("accept-language", "en-US,en;q=0.9")
        |> Plug.Session.call(options)
        |> fetch_session()
        |> TuistWeb.Plugs.LocalePlug.call([])
        |> TimezonePlug.call([])
        |> send_resp(200, "")

      # If this response completes after another tab's login, it must not
      # replace the new credential and destination with its earlier snapshot.
      refute stale.resp_cookies["session"]
      assert get_session(stale, :user_return_to) == "/old-preview"
    end
  end
end
