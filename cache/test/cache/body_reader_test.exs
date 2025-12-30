defmodule Cache.BodyReaderTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Cache.BodyReader
  alias Plug.Adapters.Test.Conn

  describe "read/1" do
    test "handles Bandit.TransportError during initial read" do
      conn = %Plug.Conn{adapter: {Conn, nil}}

      expect(Plug.Conn, :read_body, fn _conn, _opts ->
        raise Bandit.TransportError, message: "Unrecoverable error: closed", error: :closed
      end)

      assert {:error, :cancelled, ^conn} = BodyReader.read(conn)
    end

    test "handles Bandit.TransportError during chunked read" do
      conn = %Plug.Conn{adapter: {Conn, nil}}
      chunk = String.duplicate("x", 200_000)

      # First call returns :more to trigger chunked read, second call raises
      call_count = :counters.new(1, [])

      expect(Plug.Conn, :read_body, 2, fn conn, _opts ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count == 0 do
          {:more, chunk, conn}
        else
          raise Bandit.TransportError, message: "Unrecoverable error: closed", error: :closed
        end
      end)

      assert {:error, :cancelled, ^conn} = BodyReader.read(conn)
    end
  end
end
