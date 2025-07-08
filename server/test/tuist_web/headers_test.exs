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
end
