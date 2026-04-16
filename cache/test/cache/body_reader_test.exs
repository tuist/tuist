defmodule Cache.BodyReaderTest do
  use ExUnit.Case, async: true
  use Mimic

  import Plug.Conn

  alias Cache.BodyReader
  alias Plug.Adapters.Test.Conn

  describe "read/1" do
    test "enforces max_bytes for single-chunk bodies" do
      conn = Plug.Test.conn(:post, "/", "123456")

      assert {:error, :too_large, _conn_after} = BodyReader.read(conn, max_bytes: 5)
    end

    test "streams bodies larger than the initial read chunk to a temp file" do
      {:ok, tmp_dir} = Briefly.create(directory: true)
      body = :binary.copy("0123456789abcdef", 10_000)

      conn =
        :post
        |> Plug.Test.conn("/", body)
        |> put_private(:body_read_opts, length: 128_000, read_length: 128_000, read_timeout: 60_000)

      assert {:ok, {:file, tmp_path}, _conn_after} = BodyReader.read(conn, tmp_dir: tmp_dir)
      assert File.read!(tmp_path) == body

      File.rm(tmp_path)
    end

    test "handles Bandit.TransportError during initial read" do
      conn = %Plug.Conn{adapter: {Conn, nil}}

      expect(Plug.Conn, :read_body, fn _conn, _opts ->
        raise Bandit.TransportError, message: "Unrecoverable error: closed", error: :closed
      end)

      assert {:error, :cancelled, ^conn} = BodyReader.read(conn)
    end

    test "maps Bandit.TransportError timeout during initial read to timeout" do
      conn = %Plug.Conn{adapter: {Conn, nil}}

      expect(Plug.Conn, :read_body, fn _conn, _opts ->
        raise Bandit.TransportError, message: "Request body read timed out", error: :timeout
      end)

      assert {:error, :timeout, ^conn} = BodyReader.read(conn)
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

    test "maps Bandit.TransportError timeout during chunked read to timeout" do
      {:ok, tmp_dir} = Briefly.create(directory: true)
      conn = %Plug.Conn{adapter: {Conn, nil}}
      chunk = String.duplicate("x", 200_000)

      call_count = :counters.new(1, [])

      expect(Plug.Conn, :read_body, 2, fn conn, _opts ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count == 0 do
          {:more, chunk, conn}
        else
          raise Bandit.TransportError, message: "Request body read timed out", error: :timeout
        end
      end)

      assert {:error, :timeout, ^conn} = BodyReader.read(conn, tmp_dir: tmp_dir)
      assert File.ls!(tmp_dir) == []
    end

    test "normalizes timeout during chunked read" do
      {:ok, tmp_dir} = Briefly.create(directory: true)
      conn = %Plug.Conn{adapter: {Conn, nil}}
      chunk = String.duplicate("x", 200_000)

      call_count = :counters.new(1, [])

      expect(Plug.Conn, :read_body, 2, fn conn, _opts ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count == 0 do
          {:more, chunk, conn}
        else
          {:error, :timeout}
        end
      end)

      assert {:error, :timeout, ^conn} = BodyReader.read(conn, tmp_dir: tmp_dir)
      assert File.ls!(tmp_dir) == []
    end

    test "normalizes econnaborted during chunked read" do
      {:ok, tmp_dir} = Briefly.create(directory: true)
      conn = %Plug.Conn{adapter: {Conn, nil}}
      chunk = String.duplicate("x", 200_000)

      call_count = :counters.new(1, [])

      expect(Plug.Conn, :read_body, 2, fn conn, _opts ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count == 0 do
          {:more, chunk, conn}
        else
          {:error, :econnaborted}
        end
      end)

      assert {:error, :timeout, ^conn} = BodyReader.read(conn, tmp_dir: tmp_dir)
      assert File.ls!(tmp_dir) == []
    end
  end

  describe "read_to_device/3" do
    test "maps Bandit.TransportError timeout during chunked device writes to timeout" do
      {:ok, path} = Briefly.create()
      {:ok, device} = :file.open(path, [:write, :binary])
      conn = %Plug.Conn{adapter: {Conn, nil}}
      chunk = String.duplicate("x", 200_000)

      call_count = :counters.new(1, [])

      expect(Plug.Conn, :read_body, 2, fn conn, _opts ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count == 0 do
          {:more, chunk, conn}
        else
          raise Bandit.TransportError, message: "Request body read timed out", error: :timeout
        end
      end)

      try do
        assert {:error, :timeout, ^conn} = BodyReader.read_to_device(conn, device)
      after
        :file.close(device)
      end
    end

    test "normalizes timeout during chunked device writes" do
      {:ok, path} = Briefly.create()
      {:ok, device} = :file.open(path, [:write, :binary])
      conn = %Plug.Conn{adapter: {Conn, nil}}
      chunk = String.duplicate("x", 200_000)

      call_count = :counters.new(1, [])

      expect(Plug.Conn, :read_body, 2, fn conn, _opts ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count == 0 do
          {:more, chunk, conn}
        else
          {:error, :timeout}
        end
      end)

      try do
        assert {:error, :timeout, ^conn} = BodyReader.read_to_device(conn, device)
      after
        :file.close(device)
      end
    end

    test "normalizes econnaborted during chunked device writes" do
      {:ok, path} = Briefly.create()
      {:ok, device} = :file.open(path, [:write, :binary])
      conn = %Plug.Conn{adapter: {Conn, nil}}
      chunk = String.duplicate("x", 200_000)

      call_count = :counters.new(1, [])

      expect(Plug.Conn, :read_body, 2, fn conn, _opts ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count == 0 do
          {:more, chunk, conn}
        else
          {:error, :econnaborted}
        end
      end)

      try do
        assert {:error, :timeout, ^conn} = BodyReader.read_to_device(conn, device)
      after
        :file.close(device)
      end
    end
  end

  describe "drain/2" do
    test "honors a custom max_bytes limit" do
      conn = %Plug.Conn{adapter: {Conn, nil}}
      call_count = :counters.new(1, [])

      expect(Plug.Conn, :read_body, 2, fn conn, _opts ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count == 0 do
          {:more, String.duplicate("a", 20), conn}
        else
          {:ok, String.duplicate("b", 10), conn}
        end
      end)

      assert {:ok, _conn_after} = BodyReader.drain(conn, max_bytes: 30)
    end

    test "returns the connection for multi-chunk drains" do
      conn = %Plug.Conn{adapter: {Conn, nil}}
      call_count = :counters.new(1, [])

      expect(Plug.Conn, :read_body, 2, fn conn, _opts ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count == 0 do
          {:more, String.duplicate("a", 20), conn}
        else
          {:ok, String.duplicate("b", 10), conn}
        end
      end)

      assert {:ok, ^conn} = BodyReader.drain(conn, max_bytes: 30)
    end
  end

  describe "Content-Length enforcement" do
    test "accepts in-memory bodies when byte count matches Content-Length" do
      body = "complete payload"

      conn =
        :post
        |> Plug.Test.conn("/", body)
        |> put_req_header("content-length", Integer.to_string(byte_size(body)))

      assert {:ok, ^body, _conn_after} = BodyReader.read(conn)
    end

    test "returns :truncated when fewer bytes arrive than Content-Length declared" do
      # Simulates the HTTP adapter returning {:ok, partial, conn} after the
      # client disconnects mid-upload — the path that can persist corrupt
      # cache objects if left unchecked.
      conn = put_req_header(%Plug.Conn{adapter: {Conn, nil}}, "content-length", "10000")

      expect(Plug.Conn, :read_body, fn conn, _opts ->
        {:ok, String.duplicate("x", 200), conn}
      end)

      assert {:error, :truncated, _conn_after} = BodyReader.read(conn)
    end

    test "returns :truncated and deletes tmp file for truncated streamed bodies" do
      {:ok, tmp_dir} = Briefly.create(directory: true)

      conn = put_req_header(%Plug.Conn{adapter: {Conn, nil}}, "content-length", "800000")

      chunk = String.duplicate("x", 200_000)

      call_count = :counters.new(1, [])

      expect(Plug.Conn, :read_body, 2, fn conn, _opts ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count == 0 do
          {:more, chunk, conn}
        else
          {:ok, "", conn}
        end
      end)

      assert {:error, :truncated, _conn_after} = BodyReader.read(conn, tmp_dir: tmp_dir)
      assert File.ls!(tmp_dir) == []
    end

    test "passes through bodies without a Content-Length header" do
      conn = Plug.Test.conn(:post, "/", "no length declared")

      assert {:ok, "no length declared", _conn_after} = BodyReader.read(conn)
    end

    test "returns :truncated from read_to_device when device writes fall short" do
      {:ok, path} = Briefly.create()
      {:ok, device} = :file.open(path, [:write, :binary])

      conn = put_req_header(%Plug.Conn{adapter: {Conn, nil}}, "content-length", "10000")

      expect(Plug.Conn, :read_body, fn conn, _opts ->
        {:ok, String.duplicate("x", 200), conn}
      end)

      try do
        assert {:error, :truncated, _conn_after} = BodyReader.read_to_device(conn, device)
      after
        :file.close(device)
      end
    end
  end
end
