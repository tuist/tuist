defmodule TuistCloudWeb.RateLimitTest do
  use TuistCloudWeb.ConnCase, async: true

  alias TuistCloud.Environment
  alias TuistCloudWeb.RateLimit

  use Mimic

  describe "rate_limit/2" do
    test "allows the request when the rate limit is not reached" do
      # Given
      Hammer
      |> expect(:check_rate, fn _ip, _window, _limit -> {:allow, 1} end)

      conn = build_conn()

      # When
      got = RateLimit.rate_limit(conn, %{})

      # Then
      assert conn == got
    end

    test "raises TooManyRequestsError when the rate limit is reached" do
      # Given
      Hammer
      |> expect(:check_rate, fn _ip, _window, _limit -> {:deny, 1} end)

      conn = build_conn()

      # When
      assert_raise TuistCloudWeb.Errors.TooManyRequestsError, fn ->
        RateLimit.rate_limit(conn, %{})
      end
    end

    test "does not check rate limit when on premise" do
      # Given
      Mimic.reject(&Hammer.check_rate/3)

      Environment
      |> expect(:on_premise?, fn -> true end)

      conn = build_conn()

      # When
      got = RateLimit.rate_limit(conn, %{})

      # Then
      assert conn == got
    end
  end
end
