defmodule TuistWeb.BodyReaderTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Plug.Adapters.Test.Conn
  alias TuistWeb.BodyReader

  test "returns timeout when Bandit reports body read timeout" do
    conn = %Plug.Conn{adapter: {Conn, nil}}

    expect(Plug.Conn, :read_body, fn _conn, _opts ->
      raise Bandit.HTTPError, message: "Body read timeout", plug_status: 408
    end)

    assert {:error, :timeout, ^conn} = BodyReader.read_body(conn, [])
  end

  test "re-raises other Bandit HTTP errors" do
    conn = %Plug.Conn{adapter: {Conn, nil}}

    expect(Plug.Conn, :read_body, fn _conn, _opts ->
      raise Bandit.HTTPError, message: "Connection reset by peer", plug_status: 500
    end)

    assert_raise Bandit.HTTPError, fn ->
      BodyReader.read_body(conn, [])
    end
  end
end
