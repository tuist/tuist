defmodule TuistWeb.Plugs.CloseConnectionOnErrorPlugIntegrationTest do
  @moduledoc """
  Integration test to verify that when a response with Connection: close is sent
  before reading the request body, Bandit closes the connection immediately
  without waiting for body read timeout.

  This test requires the fix from https://github.com/mtrudel/bandit/pull/546
  """
  use ExUnit.Case, async: false

  @port 4099

  defmodule TestRouter do
    use Plug.Router

    plug(:match)
    plug(:dispatch)

    post "/early_error" do
      conn
      |> Plug.Conn.put_resp_header("connection", "close")
      |> Plug.Conn.send_resp(401, "Unauthorized")
    end

    match _ do
      Plug.Conn.send_resp(conn, 404, "Not Found")
    end
  end

  setup_all do
    opts = [
      plug: TestRouter,
      scheme: :http,
      port: @port,
      ip: {127, 0, 0, 1},
      thousand_island_options: [read_timeout: 2000]
    ]

    {:ok, _pid} = start_supervised({Bandit, opts})

    :ok
  end

  describe "Connection: close with unread body" do
    test "closes connection immediately without waiting for body read timeout" do
      # Open a raw TCP connection
      {:ok, socket} =
        :gen_tcp.connect(~c"127.0.0.1", @port, [
          :binary,
          active: false,
          packet: :raw
        ])

      # Send HTTP headers with a large Content-Length but don't send the body
      request = """
      POST /early_error HTTP/1.1\r
      Host: localhost\r
      Content-Length: 10000000\r
      \r
      """

      :ok = :gen_tcp.send(socket, request)

      # Measure how long it takes to get a response
      start_time = System.monotonic_time(:millisecond)
      {:ok, response} = :gen_tcp.recv(socket, 0, 5000)
      elapsed = System.monotonic_time(:millisecond) - start_time

      # Verify we got a 401 response
      assert response =~ "HTTP/1.1 401"
      assert response =~ "connection: close"

      # The response should come back quickly (well under the 2000ms read_timeout)
      # If the fix isn't working, this would take ~2000ms waiting for body drain timeout
      assert elapsed < 500,
             "Expected response in under 500ms but took #{elapsed}ms. " <>
               "This suggests Bandit is waiting for body read timeout instead of skipping body drain."

      # Verify the connection is closed
      assert :gen_tcp.recv(socket, 0, 100) == {:error, :closed}

      :gen_tcp.close(socket)
    end

    test "normal requests without Connection: close still work" do
      # Open a raw TCP connection
      {:ok, socket} =
        :gen_tcp.connect(~c"127.0.0.1", @port, [
          :binary,
          active: false,
          packet: :raw
        ])

      # Send a simple GET request
      request = """
      GET /not_found HTTP/1.1\r
      Host: localhost\r
      \r
      """

      :ok = :gen_tcp.send(socket, request)

      {:ok, response} = :gen_tcp.recv(socket, 0, 5000)

      assert response =~ "HTTP/1.1 404"

      :gen_tcp.close(socket)
    end
  end
end
