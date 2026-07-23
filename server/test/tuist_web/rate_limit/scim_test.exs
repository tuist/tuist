defmodule TuistWeb.RateLimit.SCIMTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts.AccountToken
  alias TuistWeb.RateLimit
  alias TuistWeb.RateLimit.SCIM

  describe "hit/1" do
    test "uses a fixed-window policy keyed by the account token", %{conn: conn} do
      window = to_timeout(minute: 1)
      conn = Plug.Conn.assign(conn, :scim_token, %AccountToken{id: "token-id"})

      expect(RateLimit, :hit, fn
        "scim:token:token-id", [limit: 600, window: ^window] ->
          {:allow, 1}
      end)

      assert SCIM.hit(conn) == {:allow, 1}
    end
  end
end
