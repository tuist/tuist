defmodule TuistWeb.HeadersTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias TuistWeb.Headers

  describe "get_cli_version/1" do
    test "when the x-tuist-cloud-cli-version header is not passed", %{conn: conn} do
      assert Headers.get_cli_version(conn) == nil
    end

    test "when the x-tuist-cloud-cli-version header is passed", %{conn: conn} do
      conn = Plug.Conn.put_req_header(conn, Headers.cli_version_header(), "1.2.3")

      assert Headers.get_cli_version(conn) ==
               Version.parse!("1.2.3")
    end

    test "when the x-tuist-cloud-cli-version header is passed but is invalid", %{conn: conn} do
      # Given
      conn = Plug.Conn.put_req_header(conn, Headers.cli_version_header(), "x.y.z")

      # When/Then
      assert Headers.get_cli_version(conn) == nil
    end
  end

  describe "get_client_feature_flags/1" do
    test "returns an empty set when the header is missing", %{conn: conn} do
      assert Headers.get_client_feature_flags(conn) == MapSet.new()
    end

    test "returns normalized client feature flags from the header", %{conn: conn} do
      conn =
        Plug.Conn.put_req_header(
          conn,
          Headers.client_feature_flags_header(),
          "A, b, , a"
        )

      assert Headers.get_client_feature_flags(conn) == MapSet.new(["A", "B"])
    end

    test "returns normalized client feature flags from repeated header values", %{conn: conn} do
      header = Headers.client_feature_flags_header()
      # Plug.Conn.put_req_header/3 replaces; to simulate HTTP's multi-value
      # headers we prepend directly onto req_headers.
      conn = %{conn | req_headers: [{header, "A, b"}, {header, " c , a"} | conn.req_headers]}

      assert Headers.get_client_feature_flags(conn) == MapSet.new(["A", "B", "C"])
    end
  end

  describe "get_client_feature_flag/2" do
    test "returns whether the feature flag is enabled for logical feature names", %{conn: conn} do
      conn =
        Headers.put_client_feature_flags(conn, [
          "a",
          "b"
        ])

      assert Headers.get_client_feature_flag(conn, "A")
      assert Headers.get_client_feature_flag(conn, "b")
      assert Headers.get_client_feature_flag(conn, :a)
      refute Headers.get_client_feature_flag(conn, "missing")
    end
  end

  describe "put_client_feature_flags/2" do
    test "encodes map sets as feature flag names", %{conn: conn} do
      conn = Headers.put_client_feature_flags(conn, MapSet.new(["b", "A"]))

      assert Plug.Conn.get_req_header(conn, Headers.client_feature_flags_header()) == ["A,B"]
    end
  end
end
