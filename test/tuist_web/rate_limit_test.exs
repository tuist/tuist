defmodule TuistWeb.RateLimitTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Hammer.ETS.FixWindow
  alias Tuist.Environment
  alias TuistWeb.RateLimit

  describe "rate_limit/2" do
    test "allows the request when the rate limit is not reached" do
      # Given
      expect(FixWindow, :hit, fn _table, _ip, _window, _limit, _increment -> {:allow, 1} end)
      conn = build_conn()

      # When
      got = RateLimit.rate_limit(conn, %{})

      # Then
      assert conn == got
    end

    test "raises TooManyRequestsError when the rate limit is reached" do
      # Given
      expect(FixWindow, :hit, fn _table, _ip, _window, _limit, _increment -> {:deny, 1} end)
      conn = build_conn()

      # When
      assert_raise TuistWeb.Errors.TooManyRequestsError, fn ->
        RateLimit.rate_limit(conn, %{})
      end
    end

    test "does not check rate limit when on premise" do
      # Given
      Mimic.reject(&FixWindow.hit/5)

      expect(Environment, :on_premise?, fn -> true end)
      conn = build_conn()

      # When
      got = RateLimit.rate_limit(conn, %{})

      # Then
      assert conn == got
    end
  end
end
