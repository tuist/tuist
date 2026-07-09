defmodule TuistRegistryWeb.RouterTest do
  use TuistRegistryWeb.ConnCase

  describe "GET /metrics" do
    test "is not exposed by the public registry endpoint", %{conn: conn} do
      conn = get(conn, "/metrics")

      assert conn.status == 404
    end
  end
end
