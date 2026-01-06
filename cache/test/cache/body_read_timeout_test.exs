defmodule Cache.BodyReadTimeoutTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Cache.BodyReadTimeout
  alias Plug.Adapters.Test.Conn

  test "returns timeout when Bandit reports body read timeout" do
    conn = %Plug.Conn{adapter: {Conn, nil}}

    expect(Plug.Conn, :read_body, fn _conn, _opts ->
      raise Bandit.HTTPError, message: "Body read timeout", plug_status: 408
    end)

    assert {:error, :timeout, ^conn} = BodyReadTimeout.read_body(conn, [])
  end

  test "re-raises other Bandit HTTP errors" do
    conn = %Plug.Conn{adapter: {Conn, nil}}

    expect(Plug.Conn, :read_body, fn _conn, _opts ->
      raise Bandit.HTTPError, message: "Connection reset by peer", plug_status: 500
    end)

    assert_raise Bandit.HTTPError, fn ->
      BodyReadTimeout.read_body(conn, [])
    end
  end
end
