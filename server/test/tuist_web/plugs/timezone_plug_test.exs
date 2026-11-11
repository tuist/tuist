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
end
