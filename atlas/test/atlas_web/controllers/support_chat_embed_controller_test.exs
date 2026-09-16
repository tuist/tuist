defmodule AtlasWeb.SupportChatEmbedControllerTest do
  use AtlasWeb.ConnCase, async: true

  test "serves the Atlas chat embed script to the Tuist site", %{conn: conn} do
    conn =
      conn
      |> put_req_header("origin", "https://tuist.dev")
      |> get(~p"/support/chat.js")

    assert response(conn, 200) =~ "atlas-support-chat-session"
    assert response(conn, 200) =~ "/support/chat"
    assert response(conn, 200) =~ "parent_origin"
    assert response(conn, 200) =~ "customElements.define(\"atlas-support-chat\""
    refute response(conn, 200) =~ ~s|postMessage({type: "atlas-support-chat-session", conversation}, "*")|
    assert get_resp_header(conn, "content-type") == ["application/javascript; charset=utf-8"]
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "allows Tuist to frame the chat page", %{conn: conn} do
    conn = get(conn, ~p"/support/chat")

    assert response(conn, 200)

    assert get_resp_header(conn, "content-security-policy") == [
             "base-uri 'self'; frame-ancestors 'self' https://tuist.dev;"
           ]
  end

  test "rejects an invalid email confirmation link", %{conn: conn} do
    conn = get(conn, ~p"/support/chat/verify/not-a-valid-token")

    assert response(conn, 422) =~ "This confirmation link is invalid or has expired."
  end
end
