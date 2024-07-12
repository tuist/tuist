defmodule TuistCloudWeb.HeadersTest do
  use TuistCloudWeb.ConnCase, async: true
  alias TuistCloudWeb.Headers

  describe "get_cli_version/1" do
    test "when the x-tuist-cloud-cli-version header is not passed", %{conn: conn} do
      assert Headers.get_cli_version(conn) == nil
    end

    test "when the x-tuist-cloud-cli-version header is passed", %{conn: conn} do
      conn = Plug.Conn.put_req_header(conn, Headers.cli_version_header(), "1.2.3")

      assert Headers.get_cli_version(conn) ==
               Version.parse!("1.2.3")
    end
  end
end
