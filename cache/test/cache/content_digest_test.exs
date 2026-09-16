defmodule Cache.ContentDigestTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Cache.ContentDigest

  @body "artifact bytes"
  @digest :sha256 |> :crypto.hash(@body) |> Base.encode16(case: :lower)

  describe "declared/1" do
    test "returns nil when the request declares no digest" do
      assert ContentDigest.declared(conn(:put, "/")) == {:ok, nil}
    end

    test "normalizes a declared digest to lowercase" do
      conn = put_req_header(conn(:put, "/"), "tuist-checksum-sha256", String.upcase(@digest))

      assert ContentDigest.declared(conn) == {:ok, @digest}
    end

    test "rejects a value that is not 64 hex characters" do
      for value <- ["", "abc", String.duplicate("g", 64), @digest <> "0"] do
        conn = put_req_header(conn(:put, "/"), "tuist-checksum-sha256", value)

        assert ContentDigest.declared(conn) == {:error, :invalid_checksum}
      end
    end
  end

  describe "verify/2" do
    test "passes anything when nothing is declared" do
      assert ContentDigest.verify("any bytes", nil) == :ok
    end

    test "checks an in-memory body" do
      assert ContentDigest.verify(@body, @digest) == :ok

      assert ContentDigest.verify("other bytes", @digest) ==
               {:error, {:checksum_mismatch, @digest, sha256("other bytes")}}
    end

    test "checks a body streamed to a file" do
      {:ok, path} = Briefly.create()
      large_body = :binary.copy(@body, 200_000)
      File.write!(path, large_body)

      assert ContentDigest.verify({:file, path}, sha256(large_body)) == :ok

      assert ContentDigest.verify({:file, path}, @digest) ==
               {:error, {:checksum_mismatch, @digest, sha256(large_body)}}
    end

    test "surfaces a file that cannot be read" do
      assert {:error, :enoent} = ContentDigest.verify({:file, "/nonexistent/upload"}, @digest)
    end
  end

  describe "put_header/2" do
    test "serves a recorded digest and nothing when there is none" do
      assert get_resp_header(ContentDigest.put_header(conn(:get, "/"), @digest), "tuist-checksum-sha256") == [@digest]
      assert get_resp_header(ContentDigest.put_header(conn(:get, "/"), nil), "tuist-checksum-sha256") == []
    end
  end

  defp sha256(data), do: :sha256 |> :crypto.hash(data) |> Base.encode16(case: :lower)
end
