defmodule Tuist.GitHub.RetryTest do
  use ExUnit.Case, async: true

  alias Tuist.GitHub.Retry

  describe "should_retry?/2" do
    test "returns true for server error status codes" do
      request = %{}

      for status <- [408, 429, 500, 502, 503, 504] do
        response = %Req.Response{status: status}
        assert Retry.should_retry?(request, response) == true
      end
    end

    test "returns false for successful status codes" do
      request = %{}
      response = %Req.Response{status: 200}

      assert Retry.should_retry?(request, response) == false
    end

    test "returns false for client error status codes" do
      request = %{}

      for status <- [400, 401, 403, 404] do
        response = %Req.Response{status: status}
        assert Retry.should_retry?(request, response) == false
      end
    end

    test "returns true for transport errors" do
      request = %{}

      for reason <- [:timeout, :econnrefused, :closed] do
        error = %Req.TransportError{reason: reason}
        assert Retry.should_retry?(request, error) == true
      end
    end

    test "returns true for HTTP/2 connection errors" do
      request = %{}

      for reason <- [:unprocessed, :closed_for_writing, {:server_closed_request, :refused_stream}] do
        error = %Req.HTTPError{protocol: :http2, reason: reason}
        assert Retry.should_retry?(request, error) == true
      end
    end

    test "returns false for HTTP/2 errors with other reasons" do
      request = %{}
      error = %Req.HTTPError{protocol: :http2, reason: :other_reason}

      assert Retry.should_retry?(request, error) == false
    end

    test "returns false for other HTTP errors" do
      request = %{}
      error = %Req.HTTPError{protocol: :http1, reason: :closed_for_writing}

      assert Retry.should_retry?(request, error) == false
    end

    test "returns false for unknown errors" do
      request = %{}
      error = {:error, :unknown}

      assert Retry.should_retry?(request, error) == false
    end
  end

  describe "exponential_backoff/1" do
    test "returns exponential backoff delays" do
      assert Retry.exponential_backoff(0) == 1000
      assert Retry.exponential_backoff(1) == 2000
      assert Retry.exponential_backoff(2) == 4000
      assert Retry.exponential_backoff(3) == 8000
    end
  end

  describe "retry_options/0" do
    test "returns correct retry configuration" do
      options = Retry.retry_options()

      assert Keyword.has_key?(options, :retry)
      assert Keyword.has_key?(options, :max_retries)
      assert Keyword.has_key?(options, :retry_delay)

      assert Keyword.get(options, :max_retries) == 3
      assert is_function(Keyword.get(options, :retry), 2)
      assert is_function(Keyword.get(options, :retry_delay), 1)
    end

    test "retry function in options works correctly" do
      options = Retry.retry_options()
      retry_fn = Keyword.get(options, :retry)

      request = %{}
      error = %Req.HTTPError{protocol: :http2, reason: :closed_for_writing}

      assert retry_fn.(request, error) == true
    end

    test "retry_delay function in options works correctly" do
      options = Retry.retry_options()
      delay_fn = Keyword.get(options, :retry_delay)

      assert delay_fn.(0) == 1000
      assert delay_fn.(1) == 2000
    end
  end
end
