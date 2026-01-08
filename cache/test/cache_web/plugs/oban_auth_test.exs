defmodule CacheWeb.Plugs.ObanAuthTest do
  use ExUnit.Case, async: true

  import Mimic
  import Plug.Conn
  import Plug.Test

  alias CacheWeb.Plugs.ObanAuth

  setup :verify_on_exit!

  describe "call/2" do
    test "returns 404 when oban dashboard is disabled" do
      expect(Cache.Config, :oban_dashboard_enabled?, fn -> false end)

      conn = conn(:get, "/oban")
      result = ObanAuth.call(conn, ObanAuth.init([]))

      assert result.status == 404
      assert result.halted == true
    end

    test "requires basic auth when oban dashboard is enabled" do
      expect(Cache.Config, :oban_dashboard_enabled?, fn -> true end)
      expect(Cache.Config, :oban_web_credentials, fn -> [username: "admin", password: "secret"] end)

      conn = conn(:get, "/oban")
      result = ObanAuth.call(conn, ObanAuth.init([]))

      assert result.status == 401
      assert get_resp_header(result, "www-authenticate") == ["Basic realm=\"Application\""]
    end

    test "allows access with valid credentials when oban dashboard is enabled" do
      expect(Cache.Config, :oban_dashboard_enabled?, fn -> true end)
      expect(Cache.Config, :oban_web_credentials, fn -> [username: "admin", password: "secret"] end)

      credentials = Base.encode64("admin:secret")

      conn =
        :get
        |> conn("/oban")
        |> put_req_header("authorization", "Basic #{credentials}")

      result = ObanAuth.call(conn, ObanAuth.init([]))

      refute result.halted
      refute result.status == 401
    end

    test "rejects invalid credentials when oban dashboard is enabled" do
      expect(Cache.Config, :oban_dashboard_enabled?, fn -> true end)
      expect(Cache.Config, :oban_web_credentials, fn -> [username: "admin", password: "secret"] end)

      credentials = Base.encode64("admin:wrong")

      conn =
        :get
        |> conn("/oban")
        |> put_req_header("authorization", "Basic #{credentials}")

      result = ObanAuth.call(conn, ObanAuth.init([]))

      assert result.status == 401
      assert result.halted == true
    end
  end
end
