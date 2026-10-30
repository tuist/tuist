defmodule TuistWeb.Plugs.DrainingPlugTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias TuistWeb.Draining
  alias TuistWeb.Plugs.DrainingPlug

  defmodule Router do
    use Plug.Router

    plug(DrainingPlug)
    plug(:match)
    plug(:dispatch)

    get "/report" do
      Plug.Conn.send_resp(conn, 200, "ok")
    end
  end

  setup do
    on_exit(fn -> :persistent_term.erase(Draining) end)
    :ok
  end

  defp respond(conn, status) do
    conn
    |> DrainingPlug.call([])
    |> Plug.Conn.send_resp(status, "")
  end

  describe "call/2" do
    test "keeps connections alive while the server is not draining" do
      conn = respond(conn(:get, "/"), 200)

      assert Plug.Conn.get_resp_header(conn, "connection") == []
    end

    test "closes HTTP/1.1 connections after the response while draining" do
      Draining.start()

      conn = respond(conn(:post, "/"), 201)

      assert Plug.Conn.get_resp_header(conn, "connection") == ["close"]
    end

    test "closes the connection of a request that started before draining" do
      conn = DrainingPlug.call(conn(:get, "/"), [])
      Draining.start()

      conn = Plug.Conn.send_resp(conn, 200, "")

      assert Plug.Conn.get_resp_header(conn, "connection") == ["close"]
    end

    test "never sends the header on HTTP/2, which forbids it" do
      Draining.start()

      conn =
        :get
        |> conn("/")
        |> put_http_protocol(:"HTTP/2")
        |> respond(200)

      assert Plug.Conn.get_resp_header(conn, "connection") == []
    end
  end

  describe "with Bandit" do
    setup do
      {:ok, server} = start_supervised({Bandit, plug: Router, scheme: :http, port: 0, ip: {127, 0, 0, 1}})
      {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
      %{port: port}
    end

    defp request(socket) do
      :ok = :gen_tcp.send(socket, "GET /report HTTP/1.1\r\nhost: localhost\r\n\r\n")
      {:ok, response} = :gen_tcp.recv(socket, 0, 5_000)
      response
    end

    test "an HTTP/1.1 connection serves more requests while the server is not draining", %{port: port} do
      {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])

      assert request(socket) =~ "HTTP/1.1 200"
      assert request(socket) =~ "HTTP/1.1 200"
    end

    test "an HTTP/1.1 connection closes after a complete response while draining", %{port: port} do
      {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
      Draining.start()

      response = request(socket)

      assert response =~ "HTTP/1.1 200"
      assert response =~ "connection: close"
      assert response =~ "\r\n\r\nok"
      assert :gen_tcp.recv(socket, 0, 1_000) == {:error, :closed}
    end

    test "an HTTP/2 connection keeps serving while draining", %{port: port} do
      {:ok, conn} = Mint.HTTP.connect(:http, "127.0.0.1", port, protocols: [:http2], mode: :passive)
      Draining.start()

      {conn, first} = http2_get(conn)
      {conn, second} = http2_get(conn)

      for response <- [first, second] do
        assert response.status == 200
        assert response.body == "ok"
        refute List.keymember?(response.headers, "connection", 0)
      end

      assert Mint.HTTP.open?(conn)
      Mint.HTTP.close(conn)
    end

    defp http2_get(conn) do
      {:ok, conn, ref} = Mint.HTTP.request(conn, "GET", "/report", [], nil)
      collect(conn, ref, %{headers: [], body: ""})
    end

    defp collect(conn, ref, response) do
      {:ok, conn, parts} = Mint.HTTP.recv(conn, 0, 5_000)

      response =
        Enum.reduce(parts, response, fn
          {:status, ^ref, status}, acc -> Map.put(acc, :status, status)
          {:headers, ^ref, headers}, acc -> %{acc | headers: acc.headers ++ headers}
          {:data, ^ref, data}, acc -> %{acc | body: acc.body <> data}
          {:done, ^ref}, acc -> Map.put(acc, :done, true)
          _, acc -> acc
        end)

      if response[:done], do: {conn, response}, else: collect(conn, ref, response)
    end
  end
end
