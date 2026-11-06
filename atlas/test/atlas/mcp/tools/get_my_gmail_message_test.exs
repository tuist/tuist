defmodule Atlas.MCP.Tools.GetMyGmailMessageTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Connections.Connection
  alias Atlas.Connections.Gmail
  alias Atlas.MCP.Tools.GetMyGmailMessage

  test "reads a full message preferring plain text, falling back to stripped HTML" do
    user = insert_user!()
    insert_google!(user, "own-token", [Gmail.scope()])

    http(fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["format"] == "full"

      parts =
        case conn.request_path do
          "/gmail/v1/users/me/messages/plain" ->
            [part("text/html", "<p>ignored</p>"), part("text/plain", "Hello Pedro,\nsee you")]

          "/gmail/v1/users/me/messages/html" ->
            [part("text/html", "<style>p{}</style><p>Quarterly <b>numbers</b></p><script>x()</script>")]
        end

      Req.Test.json(conn, %{
        "id" => Path.basename(conn.request_path),
        "threadId" => "t1",
        "snippet" => "",
        "payload" => %{"mimeType" => "multipart/alternative", "headers" => [], "parts" => parts}
      })
    end)

    conn = %{assigns: %{current_user: user, audit_interface: "mcp"}}

    assert {:ok, %{message: %{body: "Hello Pedro,\nsee you"}}} =
             execute_tool(GetMyGmailMessage, conn, %{"id" => "plain"})

    assert {:ok, %{message: %{body: body}}} = execute_tool(GetMyGmailMessage, conn, %{"id" => "html"})
    assert body =~ "Quarterly"
    assert body =~ "numbers"
    refute body =~ "<"
    refute body =~ "x()"
    refute body =~ "p{}"

    assert {:error, _} = GetMyGmailMessage.execute(conn, %{"id" => "../../drafts"})
  end

  defp part(type, text), do: %{"mimeType" => type, "body" => %{"data" => Base.url_encode64(text)}}

  defp insert_google!(user, token, scopes) do
    %Connection{user_id: user.id, provider: "google"}
    |> Connection.changeset(%{
      provider_user_id: "google-#{user.id}",
      account_name: user.email,
      access_token: token,
      refresh_token: "refresh",
      scopes: scopes
    })
    |> Repo.insert!()
  end

  defp http(plug), do: stub(Req, :request, fn opts -> Req.request(Req.new(Keyword.put(opts, :plug, plug)), []) end)
end
