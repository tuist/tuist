defmodule TuistWeb.RateLimit.OnceEventsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Environment
  alias TuistWeb.RateLimit.OnceEvents

  defmodule HeadersAdapter do
    @moduledoc false
    def get_headers(headers), do: headers
  end

  setup do
    stub(Environment, :once_events_rate_limit_bucket_size, fn -> 2 end)
    :ok
  end

  test "refuses calls over the limit before the service runs, and counts each address on its own" do
    busy = stream(%{"x-forwarded-for" => address()})
    quiet = stream(%{"x-forwarded-for" => address()})

    assert {:ok, _} = call(busy)
    assert {:ok, _} = call(busy)

    assert {:error, %GRPC.RPCError{} = error} = call(busy)
    assert error.status == GRPC.Status.resource_exhausted()
    refute_received :service_ran_for_third_call

    assert {:ok, _} = call(quiet)
  end

  test "uses the address the ingress set, not one a client appended" do
    first = address()
    streams = for suffix <- [", 198.51.100.1", ", 198.51.100.2", ""], do: stream(%{"x-forwarded-for" => first <> suffix})

    assert [{:ok, _}, {:ok, _}, {:error, %GRPC.RPCError{}}] = Enum.map(streams, &call/1)
  end

  test "does not limit calls that carry no forwarded address" do
    results = for _ <- 1..10, do: call(stream(%{}))

    assert Enum.all?(results, &match?({:ok, _}, &1))
  end

  test "an empty or blank forwarded address is not limited either" do
    results = for header <- ["", "  ", ","], _ <- 1..4, do: call(stream(%{"x-forwarded-for" => header}))

    assert Enum.all?(results, &match?({:ok, _}, &1))
  end

  test "the header name is matched whatever its case" do
    shared = address()
    streams = for name <- ["X-Forwarded-For", "x-forwarded-for", "X-FORWARDED-FOR"], do: stream(%{name => shared})

    assert [{:ok, _}, {:ok, _}, {:error, %GRPC.RPCError{}}] = Enum.map(streams, &call/1)
  end

  defp call(stream) do
    OnceEvents.call(%{}, stream, fn _req, stream -> {:ok, stream} end, OnceEvents.init([]))
  end

  defp stream(headers), do: %GRPC.Server.Stream{adapter: HeadersAdapter, payload: headers}

  defp address, do: "10.#{:rand.uniform(250)}.#{:rand.uniform(250)}.#{System.unique_integer([:positive])}"
end
