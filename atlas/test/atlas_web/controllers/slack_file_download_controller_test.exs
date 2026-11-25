defmodule AtlasWeb.SlackFileDownloadControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  alias Atlas.Connections.Connection
  alias Atlas.Connections.Slack
  alias Atlas.MCP.ToolCase
  alias Atlas.MCP.Tools.DownloadMySlackFile
  alias Atlas.Repo

  @scopes ~w(search:read chat:write channels:history groups:history im:history mpim:history files:read)
  @pdf "%PDF-1.7 signed DPA"

  setup %{conn: conn} do
    {_conn, user} = log_in_user(conn)
    {_conn, other} = log_in_user(conn)
    insert_slack!(other, "xoxp-other")
    insert_slack!(user, "xoxp-own")
    %{user: user, conn: build_conn()}
  end

  test "the tool's link serves the file fetched with the signing user's token, without a session", %{
    conn: conn,
    user: user
  } do
    slack(fn
      %{request_path: "/api/files.info"} = conn ->
        assert ["Bearer xoxp-own"] = get_req_header(conn, "authorization")
        assert fetch_query_params(conn).query_params["file"] == "F0DPA"
        Req.Test.json(conn, %{"ok" => true, "file" => file()})

      %{host: "files.slack.com", request_path: "/files-pri/T1-F0DPA/download/dpa.pdf"} = conn ->
        assert ["Bearer xoxp-own"] = get_req_header(conn, "authorization")
        conn |> put_resp_content_type("application/pdf") |> send_resp(200, @pdf)
    end)

    tool_conn = %{assigns: %{current_user: user, audit_interface: "mcp"}}

    assert {:ok, %{file: %{name: "Signed DPA.pdf", size: 19}, download_url: url}} =
             ToolCase.execute_tool(DownloadMySlackFile, tool_conn, %{"file_id" => "F0DPA"})

    %URI{path: path, query: query} = URI.parse(url)
    conn = get(conn, path <> "?" <> query)

    assert response(conn, 200) == @pdf
    assert get_resp_header(conn, "content-type") == ["application/pdf"]
    assert get_resp_header(conn, "content-disposition") == [~s(attachment; filename="Signed DPA.pdf")]
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "a token is bound to its file and expires", %{conn: conn, user: user} do
    stub(Req, :request, fn _ -> flunk("must not reach Slack") end)
    %URI{query: query} = URI.parse(Slack.download_url(user, "F0DPA"))

    assert conn |> get("/connections/slack/files/F0OTHER?" <> query) |> response(404)
    assert conn |> get("/connections/slack/files/F0DPA") |> response(404)

    expired =
      Phoenix.Token.sign(AtlasWeb.Endpoint, "slack-file-download", %{"user_id" => user.id, "file_id" => "F0DPA"},
        signed_at: System.system_time(:second) - Slack.download_max_age() - 1
      )

    assert conn |> get("/connections/slack/files/F0DPA?" <> URI.encode_query(%{"token" => expired})) |> response(410)
  end

  test "external, oversized and off-Slack files are refused before any download", %{user: user} do
    tool_conn = %{assigns: %{current_user: user, audit_interface: "mcp"}}

    for {overrides, expected} <- [
          {%{"is_external" => true}, "outside Slack"},
          {%{"size" => Slack.max_file_bytes() + 1}, "downloads are limited"},
          {%{"url_private_download" => "https://evil.example/dpa.pdf"}, "unavailable"}
        ] do
      slack(fn %{request_path: "/api/files.info"} = conn ->
        Req.Test.json(conn, %{"ok" => true, "file" => Map.merge(file(), overrides)})
      end)

      assert {:error, message} = DownloadMySlackFile.execute(tool_conn, %{"file_id" => "F0DPA"})
      assert message =~ expected
    end
  end

  defp file do
    %{
      "id" => "F0DPA",
      "name" => "Signed DPA.pdf",
      "title" => "Signed DPA",
      "mimetype" => "application/pdf",
      "filetype" => "pdf",
      "size" => byte_size(@pdf),
      "url_private_download" => "https://files.slack.com/files-pri/T1-F0DPA/download/dpa.pdf"
    }
  end

  defp insert_slack!(user, token) do
    %Connection{user_id: user.id, provider: "slack"}
    |> Connection.changeset(%{
      provider_user_id: "U#{user.id}",
      account_name: "slack-user",
      workspace_id: "T1",
      access_token: token,
      scopes: @scopes
    })
    |> Repo.insert!()
  end

  defp slack(plug), do: stub(Req, :request, fn opts -> Req.request(Req.new(Keyword.put(opts, :plug, plug)), []) end)
end
