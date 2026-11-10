defmodule Atlas.MCP.Tools.GetMyGmailMessageTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Connections.Connection
  alias Atlas.Connections.Gmail
  alias Atlas.Documents
  alias Atlas.Documents.Storage
  alias Atlas.MCP.Tools.GetMyGmailMessage
  alias Atlas.MCP.Tools.SaveMyGmailAttachment

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

  describe "attachments" do
    # A receipt email: text body, a small inline image and a PDF Gmail serves
    # through the attachments endpoint. The PDF bytes are not valid UTF-8.
    @pdf <<"%PDF-1.4 receipt ", 0xFF, 0xFE, 0x00, " total 1054.00">>

    setup do
      test_pid = self()

      http(fn conn ->
        send(test_pid, {:gmail, conn.request_path})

        case conn.request_path do
          "/gmail/v1/users/me/messages/receipt" ->
            Req.Test.json(conn, %{
              "id" => "receipt",
              "threadId" => "t1",
              "snippet" => "",
              "payload" => %{
                "partId" => "",
                "mimeType" => "multipart/mixed",
                "headers" => [%{"name" => "Subject", "value" => "Invoice ORD25180"}],
                "parts" => [
                  %{
                    "partId" => "0",
                    "mimeType" => "text/plain",
                    "filename" => "",
                    "body" => %{"data" => Base.url_encode64("See attached.")}
                  },
                  %{
                    "partId" => "1",
                    "mimeType" => "image/png",
                    "filename" => "logo.png",
                    "body" => %{"size" => 3, "data" => Base.url_encode64("PNG")}
                  },
                  %{
                    "partId" => "2",
                    "mimeType" => "application/pdf",
                    "filename" => "invoice-ORD25180.pdf",
                    "body" => %{"size" => byte_size(@pdf), "attachmentId" => "ANGjdJ_fresh-id"}
                  }
                ]
              }
            })

          "/gmail/v1/users/me/messages/receipt/attachments/ANGjdJ_fresh-id" ->
            Req.Test.json(conn, %{"size" => byte_size(@pdf), "data" => Base.url_encode64(@pdf)})
        end
      end)

      :ok
    end

    test "get_my_gmail_message lists attachments by part id" do
      user = insert_user!()
      insert_google!(user, "own-token", [Gmail.scope()])
      conn = %{assigns: %{current_user: user, audit_interface: "mcp"}}

      assert {:ok, %{message: %{attachments: attachments}}} =
               execute_tool(GetMyGmailMessage, conn, %{"id" => "receipt"})

      assert attachments == [
               %{"part_id" => "1", "filename" => "logo.png", "mime_type" => "image/png", "size" => 3},
               %{
                 "part_id" => "2",
                 "filename" => "invoice-ORD25180.pdf",
                 "mime_type" => "application/pdf",
                 "size" => byte_size(@pdf)
               }
             ]
    end

    test "save_my_gmail_attachment stores the attachment's exact bytes in the document library" do
      user = insert_user!(%{scopes: ["documents:write"]})
      insert_google!(user, "own-token", [Gmail.scope()])
      conn = %{assigns: %{current_user: user, audit_interface: "mcp"}}

      assert {:ok, result} =
               execute_tool(SaveMyGmailAttachment, conn, %{"message_id" => "receipt", "part_id" => "2"})

      assert_received {:gmail, "/gmail/v1/users/me/messages/receipt/attachments/ANGjdJ_fresh-id"}
      assert %{filename: "invoice-ORD25180.pdf", content_type: "application/pdf", byte_size: byte_size} = result
      assert byte_size == byte_size(@pdf)

      document = Documents.get_document(result.document_id)
      assert document.source == "email"
      assert document.uploaded_by_id == user.id
      assert {:ok, %{body: @pdf}} = Storage.get_object(document.storage_key)

      assert {:ok, inline} = execute_tool(SaveMyGmailAttachment, conn, %{"message_id" => "receipt", "part_id" => "1"})
      assert {:ok, %{body: "PNG"}} = Storage.get_object(Documents.get_document(inline.document_id).storage_key)
    end

    test "save_my_gmail_attachment refuses non-attachment parts and callers without documents:write" do
      writer = insert_user!(%{scopes: ["documents:write"]})
      reader = insert_user!()
      insert_google!(writer, "writer-token", [Gmail.scope()])
      insert_google!(reader, "reader-token", [Gmail.scope()])

      writer_conn = %{assigns: %{current_user: writer, audit_interface: "mcp"}}
      reader_conn = %{assigns: %{current_user: reader, audit_interface: "mcp"}}

      assert {:error, _} = SaveMyGmailAttachment.execute(writer_conn, %{"message_id" => "receipt", "part_id" => "0"})
      assert {:error, _} = SaveMyGmailAttachment.execute(writer_conn, %{"message_id" => "receipt", "part_id" => "9"})

      assert {:error, message} =
               SaveMyGmailAttachment.execute(reader_conn, %{"message_id" => "receipt", "part_id" => "2"})

      assert message =~ "documents:write"
      refute_received {:gmail, "/gmail/v1/users/me/messages/receipt/attachments/" <> _}
    end
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
