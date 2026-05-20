defmodule TuistWeb.Plugs.SlackCommunityRedirectPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias TuistWeb.Plugs.SlackCommunityRedirectPlug

  @slack_invite_url Application.compile_env!(:tuist, [:urls, :slack_invite])

  describe "call/2" do
    test "redirects requests sent to the Slack community host", %{conn: conn} do
      conn =
        conn
        |> Map.put(:host, "slack.tuist.dev")
        |> SlackCommunityRedirectPlug.call([])

      assert conn.status == 302
      assert redirected_to(conn, 302) == @slack_invite_url
      assert conn.halted
    end

    test "passes through requests for other hosts", %{conn: conn} do
      conn = SlackCommunityRedirectPlug.call(conn, [])

      assert conn.status == nil
      refute conn.halted
    end
  end
end
