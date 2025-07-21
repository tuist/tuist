defmodule TuistWeb.AppleAppSiteAssociationControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  describe "GET /.well-known/apple-app-site-association" do
    test "returns the apple app site association JSON", %{conn: conn} do
      conn = get(conn, "/.well-known/apple-app-site-association")

      assert json_response(conn, 200) == %{
               "applinks" => %{
                 "apps" => [],
                 "details" => [
                   %{
                     "appID" => "U6LC622NKF.dev.tuist.app",
                     "paths" => ["/*/*/previews/*"]
                   }
                 ]
               }
             }

      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]
    end
  end
end
