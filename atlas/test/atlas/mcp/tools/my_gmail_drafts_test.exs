defmodule Atlas.MCP.Tools.MyGmailDraftsTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Audit.Activity
  alias Atlas.Connections.Connection
  alias Atlas.Connections.Gmail
  alias Atlas.Documents
  alias Atlas.MCP
  alias Atlas.MCP.Proxy
  alias Atlas.MCP.Server
  alias Atlas.MCP.ToolApproval
  alias Atlas.MCP.Tools.CreateMyGmailDraft
  alias Atlas.MCP.Tools.GetMyGmailDraft
  alias Atlas.MCP.Tools.SendMyGmailDraft
  alias Atlas.MCP.Tools.UpdateMyGmailDraft

  test "a reply draft is plain text, threaded under the original and keeps its UTF-8 subject and body" do
    user = insert_google!([Gmail.scope(), Gmail.compose_scope()])

    gmail(fn
      "GET", "/gmail/v1/users/me/messages/orig", conn ->
        assert conn.query_params["format"] == "metadata"

        Req.Test.json(conn, %{
          "id" => "orig",
          "threadId" => "thread-1",
          "payload" => %{
            "headers" => [
              %{"name" => "Message-Id", "value" => "<orig@mail.example>"},
              %{"name" => "References", "value" => "<root@mail.example>"}
            ]
          }
        })

      "POST", "/upload/gmail/v1/users/me/drafts", conn ->
        message = conn |> uploaded() |> Map.fetch!("message")
        send(self(), {:created, message})
        Req.Test.json(conn, %{"id" => "draft-1", "message" => %{"id" => "msg-1", "threadId" => "thread-1"}})
    end)

    args = %{
      "to" => ["anna@example.com", "ben@example.org"],
      "cc" => ["cleo@example.net"],
      "subject" => "Re: Vertrag für Käthe",
      "body" => "Hallo Käthe,\n\nanbei die Änderungen.",
      "reply_to_message_id" => "orig"
    }

    assert {:ok, %{draft: draft}} = execute_tool(CreateMyGmailDraft, agent_conn(user), args)
    assert draft.id == "draft-1"
    assert draft.thread_id == "thread-1"
    assert draft.in_reply_to == "<orig@mail.example>"

    assert_received {:created, %{"threadId" => "thread-1", "raw" => raw}}
    {headers, body} = parse(raw)
    assert headers["to"] == "anna@example.com, ben@example.org"
    assert headers["cc"] == "cleo@example.net"
    assert headers["in-reply-to"] == "<orig@mail.example>"
    assert headers["references"] == "<root@mail.example> <orig@mail.example>"
    assert headers["content-type"] == "text/plain; charset=UTF-8"
    refute Map.has_key?(headers, "bcc")
    assert decode_words(headers["subject"]) == "Re: Vertrag für Käthe"
    assert body == "Hallo Käthe,\n\nanbei die Änderungen."

    activity = Repo.get_by!(Activity, action: "connection.gmail_draft_created", actor_id: user.id)
    assert activity.metadata["draft_id"] == "draft-1"
    assert activity.metadata["reply"] == true
    refute JSON.encode!(activity.metadata) =~ ~r/anna|Käthe|Vertrag/
  end

  test "Markdown and HTML create and replace rich drafts with UTF-8 plain-text alternatives" do
    user = insert_google!([Gmail.compose_scope()])

    gmail(fn
      "GET", "/gmail/v1/users/me/drafts/draft-1", conn ->
        Req.Test.json(conn, draft_payload("Old", "Old"))

      method, path, conn when method in ["POST", "PUT"] ->
        assert path in ["/upload/gmail/v1/users/me/drafts", "/upload/gmail/v1/users/me/drafts/draft-1"]
        send(self(), {:rich, uploaded(conn)["message"]["raw"]})
        Req.Test.json(conn, %{"id" => "draft-1", "message" => %{"id" => "msg-1"}})
    end)

    for {format, source, expected_html, expected_plain} <- [
          {"markdown", "Hallo **Käthe**\n\n[Details](https://example.org/details)", "<strong>Käthe</strong>",
           "Hallo **Käthe**\n\n[Details](https://example.org/details)"},
          {"html",
           "<style>hidden</style><p>Hallo <em>Käthe</em>, pay &euro;100 to A&amp;B.</p><p><a href='https://example.org/pay?a=1&amp;b=2'>Pay <strong>invoice</strong></a><br>Thanks &#33;</p><!-- hidden -->",
           "<em>Käthe</em>", "Hallo Käthe, pay €100 to A&B.\nPay invoice (https://example.org/pay?a=1&b=2)\nThanks !"}
        ],
        module <- [CreateMyGmailDraft, UpdateMyGmailDraft] do
      args = %{"to" => ["anna@example.com"], "subject" => "Rich", "body" => source, "body_format" => format}
      args = if module == UpdateMyGmailDraft, do: Map.put(args, "draft_id", "draft-1"), else: args
      assert {:ok, %{draft: draft}} = execute_tool(module, agent_conn(user), args)
      assert draft.body_html =~ expected_html
      assert_received {:rich, raw}
      [headers, content] = raw |> Base.url_decode64!(padding: false) |> String.split("\r\n\r\n", parts: 2)
      [_, boundary] = Regex.run(~r/multipart\/alternative; boundary="([^"]+)"/, headers)
      [plain, html, closing] = String.split(content, "--#{boundary}", trim: true)
      assert closing == "--\r\n"

      for {part, type} <- [{plain, "text/plain"}, {html, "text/html"}] do
        assert part =~ "Content-Type: #{type}; charset=UTF-8"
        [_, encoded] = String.split(part, "\r\n\r\n", parts: 2)
        decoded = encoded |> String.replace("\r\n", "") |> Base.decode64!()
        assert decoded =~ "Käthe"
        if type == "text/html", do: assert(decoded =~ expected_html)
        if type == "text/plain", do: assert(decoded == expected_plain)
      end
    end
  end

  test "rich draft reads include both plain text and bounded HTML source" do
    user = insert_google!([Gmail.compose_scope()])
    html = "<a href=\"https://example.org/details\">Read details</a>" <> String.duplicate("x", 20_000)

    payload =
      put_in(draft_payload("Review", "Read details"), ["message", "payload", "parts"], [
        %{"mimeType" => "text/html", "body" => %{"data" => Base.url_encode64(html)}}
      ])

    Process.put(:draft, payload)
    send_gmail()
    assert {:ok, %{draft: draft}} = execute_tool(GetMyGmailDraft, agent_conn(user), %{"draft_id" => "draft-1"})
    assert draft.body == "Read details"
    assert draft.body_html == String.slice(html, 0, 20_000)
  end

  test "recipients and subjects cannot inject headers, and nothing reaches Gmail" do
    user = insert_google!([Gmail.compose_scope()])
    stub(Req, :request, fn _ -> flunk("invalid drafts must not reach Gmail") end)
    base = %{"to" => ["anna@example.com"], "subject" => "Hi", "body" => "Hello"}

    for args <- [
          %{base | "to" => ["anna@example.com\r\nBcc: eve@example.com"]},
          %{base | "to" => ["Anna <anna@example.com>"]},
          %{base | "subject" => "Hi\r\nBcc: eve@example.com"},
          Map.put(base, "cc", ["eve@example.com, mallory@example.com"]),
          Map.put(base, "body_format", "text/html\r\nBcc: eve@example.com"),
          %{base | "to" => []},
          Map.put(base, "attachments", [
            %{
              "filename" => "a.pdf",
              "content_type" => "application/pdf\r\nBcc: eve@example.com",
              "content_base64" => "AA=="
            }
          ]),
          Map.put(base, "attachments", [%{"filename" => "a.pdf\r\nBcc: eve@example.com", "content_base64" => "AA=="}]),
          Map.put(base, "attachments", [%{"filename" => "a.pdf", "content_base64" => "not base64!"}])
        ] do
      assert {:error, message} = CreateMyGmailDraft.execute(agent_conn(user), args)
      refute message =~ "expired"
    end
  end

  test "drafts need the separate drafts consent, read access alone is not enough" do
    user = insert_google!([Gmail.scope()])
    stub(Req, :request, fn _ -> flunk("Gmail must not be called without gmail.compose") end)

    assert {:error, message} =
             CreateMyGmailDraft.execute(agent_conn(user), %{"to" => ["a@example.com"], "subject" => "s", "body" => "b"})

    assert message =~ "Allow Gmail drafts"
    assert {:error, message} = SendMyGmailDraft.execute(agent_conn(user), %{"draft_id" => "draft-1"})
    assert message =~ "Allow Gmail drafts"
  end

  test "an update without a reply id keeps the draft's thread and reply headers" do
    user = insert_google!([Gmail.compose_scope()])
    Process.put(:draft, draft_payload("Old subject", "Old body", in_reply_to: "<orig@mail.example>"))

    gmail(fn
      "GET", "/gmail/v1/users/me/drafts/draft-1", conn ->
        Req.Test.json(conn, Process.get(:draft))

      "PUT", "/upload/gmail/v1/users/me/drafts/draft-1", conn ->
        send(self(), {:updated, uploaded(conn)})
        Req.Test.json(conn, %{"id" => "draft-1", "message" => %{"id" => "msg-2", "threadId" => "thread-1"}})
    end)

    args = %{"draft_id" => "draft-1", "to" => ["anna@example.com"], "subject" => "Re: New", "body" => "New body"}

    assert {:ok, %{draft: %{in_reply_to: "<orig@mail.example>"}}} =
             execute_tool(UpdateMyGmailDraft, agent_conn(user), args)

    assert_received {:updated, %{"id" => "draft-1", "message" => %{"threadId" => "thread-1", "raw" => raw}}}
    {headers, body} = parse(raw)
    assert headers["in-reply-to"] == "<orig@mail.example>"
    assert headers["references"] == "<orig@mail.example>"
    assert headers["subject"] == "Re: New"
    assert body == "New body"
  end

  test "a created draft carries its attachments next to the rich body" do
    user = insert_google!([Gmail.compose_scope()])
    pdf = <<"%PDF-1.7\n", :crypto.strong_rand_bytes(200)::binary>>

    gmail(fn "POST", "/upload/gmail/v1/users/me/drafts", conn ->
      send(self(), {:created, uploaded(conn)})
      Req.Test.json(conn, %{"id" => "draft-1", "message" => %{"id" => "msg-1"}})
    end)

    args = %{
      "to" => ["anna@example.com"],
      "subject" => "Signed contract",
      "body" => "Attached, **signed**.",
      "body_format" => "markdown",
      "attachments" => [
        %{
          "filename" => "Vertrag – Käthe.pdf",
          "content_type" => "application/pdf",
          "content_base64" => Base.encode64(pdf)
        },
        %{"filename" => "notes.txt", "content_type" => "", "content_base64" => Base.encode64("ok")}
      ]
    }

    assert {:ok, %{draft: draft}} = execute_tool(CreateMyGmailDraft, agent_conn(user), args)

    assert draft.attachments == [
             %{"filename" => "Vertrag – Käthe.pdf", "mime_type" => "application/pdf", "size" => byte_size(pdf)},
             %{"filename" => "notes.txt", "mime_type" => "text/plain", "size" => 2}
           ]

    assert_received {:created, %{"message" => message}}
    refute Map.has_key?(message, "threadId")
    {headers, [{body_headers, [_plain, _html]}, {pdf_headers, pdf_body}, {txt_headers, "ok"}]} = parse(message["raw"])
    assert headers["content-type"] =~ "multipart/mixed"
    assert body_headers["content-type"] =~ "multipart/alternative"
    assert pdf_headers["content-type"] == "application/pdf"
    assert pdf_headers["content-disposition"] == "attachment; filename*=UTF-8''Vertrag%20%E2%80%93%20K%C3%A4the.pdf"
    assert pdf_body == pdf
    assert txt_headers["content-type"] == "text/plain"
    assert txt_headers["content-disposition"] == ~s(attachment; filename="notes.txt")
  end

  test "attachments can be Atlas documents, which need document access" do
    reader = insert_google!([Gmail.compose_scope()], %{scopes: ["documents:read"]})
    outsider = insert_google!([Gmail.compose_scope()])
    docx = <<"PK", :crypto.strong_rand_bytes(300)::binary>>
    docx_type = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

    {:ok, document} =
      Documents.create_from_binary(docx, %{"original_filename" => "Annex – redline.docx", "content_type" => docx_type},
        enqueue?: false
      )

    gmail(fn "POST", "/upload/gmail/v1/users/me/drafts", conn ->
      send(self(), {:created, uploaded(conn)})
      Req.Test.json(conn, %{"id" => "draft-1", "message" => %{"id" => "msg-1"}})
    end)

    args = %{
      "to" => ["legal@example.com"],
      "subject" => "Redlines",
      "body" => "Attached.",
      "attachments" => [
        %{"document_id" => document.id},
        %{"document_id" => document.id, "filename" => "renamed.docx"},
        %{"filename" => "notes.txt", "content_base64" => Base.encode64("ok")}
      ]
    }

    assert {:ok, %{draft: draft}} = execute_tool(CreateMyGmailDraft, agent_conn(reader), args)

    assert Enum.map(draft.attachments, &{&1["filename"], &1["mime_type"], &1["size"]}) == [
             {"Annex – redline.docx", docx_type, byte_size(docx)},
             {"renamed.docx", docx_type, byte_size(docx)},
             {"notes.txt", "text/plain", 2}
           ]

    assert_received {:created, %{"message" => message}}
    {_headers, [_body, {docx_headers, ^docx}, {_renamed, ^docx}, {_txt, "ok"}]} = parse(message["raw"])
    assert docx_headers["content-type"] == docx_type

    assert {:error, message} = CreateMyGmailDraft.execute(agent_conn(outsider), args)
    assert message =~ "documents:read"

    missing = %{args | "attachments" => [%{"document_id" => Ecto.UUID.generate()}]}
    assert {:error, message} = CreateMyGmailDraft.execute(agent_conn(reader), missing)
    assert message =~ "not found"

    both = %{
      args
      | "attachments" => [%{"document_id" => document.id, "filename" => "x.txt", "content_base64" => "b2s="}]
    }

    assert {:error, message} = CreateMyGmailDraft.execute(agent_conn(reader), both)
    assert message =~ "not both"
    refute_received {:created, _}
  end

  test "an update keeps the draft's attachments with only the drafts consent, unless told to drop them" do
    user = insert_google!([Gmail.compose_scope()])
    signed = :crypto.strong_rand_bytes(300)

    parts = [
      {"signed.pdf", "application/pdf", ~s(attachment; filename="signed.pdf"), signed},
      {"Vertrag – Käthe.pdf", "application/pdf", "attachment; filename*=UTF-8''Vertrag%20%E2%80%93%20K%C3%A4the.pdf",
       "vertrag"},
      {"terms.csv", ~s(text/csv; name="terms.csv"), nil, "a,b"}
    ]

    raw =
      "To: anna@example.com\r\nSubject: Contract\r\nMIME-Version: 1.0\r\n" <>
        ~s(Content-Type: multipart/mixed; boundary="b"\r\n\r\n) <>
        "--b\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nOld body\r\n" <>
        Enum.map_join(parts, fn {_name, type, disposition, data} ->
          "--b\r\nContent-Type: #{type}\r\n" <>
            if(disposition, do: "Content-Disposition: #{disposition}\r\n", else: "") <>
            "Content-Transfer-Encoding: base64\r\n\r\n#{Base.encode64(data)}\r\n"
        end) <> "--b--\r\n"

    draft =
      update_in(draft_payload("Contract", "Old body"), ["message", "payload"], fn payload ->
        Map.merge(payload, %{
          "mimeType" => "multipart/mixed",
          "parts" =>
            for {{name, type, _, data}, index} <- Enum.with_index(parts, 1) do
              %{
                "partId" => "#{index}",
                "mimeType" => type,
                "filename" => name,
                "body" => %{"attachmentId" => "att-#{index}", "size" => byte_size(data)}
              }
            end
        })
      end)

    gmail(fn
      "GET", "/gmail/v1/users/me/drafts/draft-1", conn ->
        case conn.query_params["format"] do
          "full" -> Req.Test.json(conn, draft)
          "raw" -> Req.Test.json(conn, %{"id" => "draft-1", "message" => %{"raw" => Base.url_encode64(raw)}})
        end

      # Google refuses attachment downloads to a token without Gmail read access.
      "GET", "/gmail/v1/users/me/messages/" <> _, conn ->
        conn
        |> Plug.Conn.put_status(403)
        |> Req.Test.json(%{"error" => %{"errors" => [%{"reason" => "insufficientPermissions"}]}})

      "PUT", "/upload/gmail/v1/users/me/drafts/draft-1", conn ->
        send(self(), {:updated, uploaded(conn)})
        Req.Test.json(conn, %{"id" => "draft-1", "message" => %{"id" => "msg-2", "threadId" => "thread-1"}})
    end)

    args = %{
      "draft_id" => "draft-1",
      "to" => ["anna@example.com"],
      "subject" => "Contract",
      "body" => "New body",
      "attachments" => [%{"filename" => "invoice.pdf", "content_base64" => Base.encode64("invoice")}]
    }

    assert {:ok, %{draft: %{attachments: listed}}} = execute_tool(UpdateMyGmailDraft, agent_conn(user), args)
    assert Enum.map(listed, & &1["filename"]) == ["signed.pdf", "Vertrag – Käthe.pdf", "terms.csv", "invoice.pdf"]

    assert_received {:updated, %{"id" => "draft-1", "message" => %{"threadId" => "thread-1", "raw" => raw}}}

    {_headers,
     [
       {_, "New body"},
       {signed_headers, ^signed},
       {vertrag_headers, "vertrag"},
       {csv_headers, "a,b"},
       {invoice_headers, "invoice"}
     ]} = parse(raw)

    assert signed_headers["content-type"] == "application/pdf"
    assert signed_headers["content-disposition"] == ~s(attachment; filename="signed.pdf")
    assert vertrag_headers["content-disposition"] == "attachment; filename*=UTF-8''Vertrag%20%E2%80%93%20K%C3%A4the.pdf"
    assert csv_headers["content-type"] == "text/csv"
    assert invoice_headers["content-type"] == "application/pdf"

    assert {:ok, %{draft: %{attachments: []}}} =
             execute_tool(
               UpdateMyGmailDraft,
               agent_conn(user),
               args |> Map.delete("attachments") |> Map.put("keep_attachments", false)
             )

    assert_received {:updated, %{"message" => %{"raw" => raw}}}
    assert {%{"content-type" => "text/plain; charset=UTF-8"}, "New body"} = parse(raw)
  end

  test "a reply update carries new attachments in the original thread" do
    user = insert_google!([Gmail.scope(), Gmail.compose_scope()])

    gmail(fn
      "GET", "/gmail/v1/users/me/drafts/draft-1", conn ->
        Req.Test.json(conn, draft_payload("Draft", "Old"))

      "GET", "/gmail/v1/users/me/messages/orig", conn ->
        Req.Test.json(conn, %{
          "id" => "orig",
          "threadId" => "thread-9",
          "payload" => %{"headers" => [%{"name" => "Message-ID", "value" => "<orig@mail.example>"}]}
        })

      "PUT", "/upload/gmail/v1/users/me/drafts/draft-1", conn ->
        send(self(), {:updated, uploaded(conn)})
        Req.Test.json(conn, %{"id" => "draft-1", "message" => %{"id" => "msg-2", "threadId" => "thread-9"}})
    end)

    args = %{
      "draft_id" => "draft-1",
      "to" => ["anna@example.com"],
      "subject" => "Re: Contract",
      "body" => "Signed copy attached.",
      "reply_to_message_id" => "orig",
      "attachments" => [%{"filename" => "signed.pdf", "content_base64" => Base.encode64("pdf")}]
    }

    assert {:ok, %{draft: %{in_reply_to: "<orig@mail.example>"}}} =
             execute_tool(UpdateMyGmailDraft, agent_conn(user), args)

    assert_received {:updated, %{"id" => "draft-1", "message" => %{"threadId" => "thread-9", "raw" => raw}}}
    {headers, [{_, "Signed copy attached."}, {pdf_headers, "pdf"}]} = parse(raw)
    assert headers["content-type"] =~ "multipart/mixed"
    assert headers["in-reply-to"] == "<orig@mail.example>"
    assert headers["references"] == "<orig@mail.example>"
    assert pdf_headers["content-type"] == "application/pdf"
  end

  test "keep_attachments false replaces the draft's attachments without reading them" do
    user = insert_google!([Gmail.compose_scope()])

    draft =
      update_in(draft_payload("Contract", "Body"), ["message", "payload"], fn payload ->
        Map.merge(payload, %{
          "mimeType" => "multipart/mixed",
          "parts" => [
            %{
              "partId" => "1",
              "mimeType" => "application/pdf",
              "filename" => "old.pdf",
              "body" => %{"size" => 30_000_000}
            }
          ]
        })
      end)

    gmail(fn
      "GET", "/gmail/v1/users/me/drafts/draft-1", conn ->
        assert conn.query_params["format"] == "full", "replaced attachments must not be downloaded"
        Req.Test.json(conn, draft)

      "PUT", "/upload/gmail/v1/users/me/drafts/draft-1", conn ->
        send(self(), {:updated, uploaded(conn)})
        Req.Test.json(conn, %{"id" => "draft-1", "message" => %{"id" => "msg-2"}})
    end)

    args = %{
      "draft_id" => "draft-1",
      "to" => ["anna@example.com"],
      "subject" => "Contract",
      "body" => "Body",
      "keep_attachments" => false,
      "attachments" => [%{"filename" => "new.pdf", "content_base64" => Base.encode64("new")}]
    }

    assert {:ok, %{draft: %{attachments: [%{"filename" => "new.pdf"}]}}} =
             execute_tool(UpdateMyGmailDraft, agent_conn(user), args)

    assert_received {:updated, %{"message" => %{"raw" => raw}}}

    assert {_headers, [{_, "Body"}, {%{"content-disposition" => ~s(attachment; filename="new.pdf")}, "new"}]} =
             parse(raw)
  end

  test "an update keeps empty attachments and attachments without a filename" do
    user = insert_google!([Gmail.compose_scope()])

    raw =
      "To: anna@example.com\r\nSubject: Contract\r\nMIME-Version: 1.0\r\n" <>
        ~s(Content-Type: multipart/mixed; boundary="b"\r\n\r\n) <>
        "--b\r\nContent-Type: text/plain\r\n\r\nOld\r\n" <>
        "--b\r\nContent-Type: text/csv\r\nContent-Disposition: attachment\r\n" <>
        "Content-Transfer-Encoding: base64\r\n\r\n#{Base.encode64("a,b")}\r\n" <>
        "--b\r\nContent-Type: text/plain\r\n" <>
        ~s(Content-Disposition: attachment; filename="empty.txt"\r\n) <>
        "Content-Transfer-Encoding: base64\r\n\r\n\r\n--b--\r\n"

    # Only the Content-Disposition header marks the CSV as an attachment.
    draft =
      update_in(draft_payload("Contract", "Old"), ["message", "payload"], fn payload ->
        Map.merge(payload, %{
          "mimeType" => "multipart/mixed",
          "parts" => [
            %{
              "partId" => "1",
              "mimeType" => "text/csv",
              "filename" => "",
              "headers" => [%{"name" => "Content-Disposition", "value" => "attachment"}],
              "body" => %{"attachmentId" => "att-1", "size" => 3}
            }
          ]
        })
      end)

    gmail(fn
      "GET", "/gmail/v1/users/me/drafts/draft-1", conn ->
        case conn.query_params["format"] do
          "full" -> Req.Test.json(conn, draft)
          "raw" -> Req.Test.json(conn, %{"id" => "draft-1", "message" => %{"raw" => Base.url_encode64(raw)}})
        end

      "PUT", "/upload/gmail/v1/users/me/drafts/draft-1", conn ->
        send(self(), {:updated, uploaded(conn)})
        Req.Test.json(conn, %{"id" => "draft-1", "message" => %{"id" => "msg-2"}})
    end)

    args = %{"draft_id" => "draft-1", "to" => ["anna@example.com"], "subject" => "Contract", "body" => "New"}

    assert {:ok, %{draft: %{attachments: listed}}} = execute_tool(UpdateMyGmailDraft, agent_conn(user), args)

    assert listed == [
             %{"filename" => "attachment", "mime_type" => "text/csv", "size" => 3},
             %{"filename" => "empty.txt", "mime_type" => "text/plain", "size" => 0}
           ]

    assert_received {:updated, %{"message" => %{"raw" => raw}}}
    assert {_headers, [{_, "New"}, {_, "a,b"}, {%{"content-type" => "text/plain"}, ""}]} = parse(raw)
  end

  test "an update that would push the draft's attachments past the limit is refused before any download" do
    user = insert_google!([Gmail.compose_scope()])

    draft =
      update_in(draft_payload("Contract", "Body"), ["message", "payload"], fn payload ->
        Map.merge(payload, %{
          "mimeType" => "multipart/mixed",
          "parts" => [
            %{
              "partId" => "1",
              "mimeType" => "application/pdf",
              "filename" => "big.pdf",
              "body" => %{"attachmentId" => "att-1", "size" => 18_000_000}
            }
          ]
        })
      end)

    gmail(fn "GET", "/gmail/v1/users/me/drafts/draft-1", conn ->
      assert conn.query_params["format"] == "full", "attachments must not be downloaded"
      Req.Test.json(conn, draft)
    end)

    args = %{
      "draft_id" => "draft-1",
      "to" => ["anna@example.com"],
      "subject" => "Contract",
      "body" => "Body",
      "attachments" => [%{"filename" => "one-more.txt", "content_base64" => Base.encode64("x")}]
    }

    assert {:error, message} = UpdateMyGmailDraft.execute(agent_conn(user), args)
    assert message =~ "at most 18 MB"
  end

  test "sending immediately uses the owner's mailbox without creating or consuming an Atlas approval" do
    user = insert_google!([Gmail.compose_scope()])
    Process.put(:draft, draft_payload("Renewal", "Price is 10k"))
    send_gmail()

    assert {:ok, %{message_id: "sent-1"}} = execute_tool(SendMyGmailDraft, agent_conn(user), %{"draft_id" => "draft-1"})
    assert_received :sent
    assert Repo.aggregate(ToolApproval, :count) == 0

    activity = Repo.get_by!(Activity, action: "connection.gmail_draft_sent", actor_id: user.id)
    assert activity.metadata["recipient_count"] == 2
    refute JSON.encode!(activity.metadata) =~ ~r/Renewal|10k|anna/

    # Rows left over from the old approval flow do not gate or authorize sends.
    {:approval_required, legacy} =
      MCP.authorize_tool_call(user, "gmail", "send-draft", %{"draft_id" => "draft-1", "digest" => "old"})

    assert {:ok, %{message_id: "sent-1"}} = execute_tool(SendMyGmailDraft, agent_conn(user), %{"draft_id" => "draft-1"})
    assert_received :sent
    assert Repo.reload!(legacy).status == "pending"
    assert Repo.aggregate(ToolApproval, :count) == 1
  end

  test "ambiguous sends warn the caller to check Sent and are not automatically retried" do
    user = insert_google!([Gmail.compose_scope()])

    gmail(fn
      "GET", "/gmail/v1/users/me/drafts/draft-1", conn ->
        Req.Test.json(conn, draft_payload("Renewal", "Price is 10k"))

      "POST", "/gmail/v1/users/me/drafts/send", conn ->
        send(self(), :send_attempt)
        conn |> Plug.Conn.put_status(503) |> Req.Test.json(%{})
    end)

    assert {:error, message} = SendMyGmailDraft.execute(agent_conn(user), %{"draft_id" => "draft-1"})
    assert message =~ "Check the Sent folder"
    assert message =~ "may already have been sent"
    assert_received :send_attempt
    refute_received :send_attempt
    refute Repo.exists?(ToolApproval)
  end

  test "drafts are hidden from and refused to shared identities, and sending needs a person's MCP session" do
    user = insert_google!([Gmail.compose_scope()])
    stub(Proxy, :list_hoisted_tools, fn _ -> [] end)
    stub(Req, :request, fn _ -> flunk("shared identities must not reach Gmail") end)
    slack = %{assigns: %{current_user: user, audit_interface: "slack"}}

    response = Server.handle_message(slack, %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"})
    names = Enum.map(response["result"]["tools"], & &1["name"])

    for module <- [GetMyGmailDraft, CreateMyGmailDraft, UpdateMyGmailDraft, SendMyGmailDraft] do
      refute module.name() in names
      assert {:error, "Personal Gmail is unavailable to shared Slack identities."} = module.execute(slack, %{})
    end

    for conn <- [
          %{assigns: %{current_user: user, mcp_claims: %{"slack_agent" => true}}},
          %{assigns: %{current_user: user, audit_interface: "worker"}}
        ] do
      assert {:error, _} = SendMyGmailDraft.execute(conn, %{"draft_id" => "draft-1"})
    end
  end

  test "the MCP audit trail never keeps draft recipients or content" do
    user = insert_user!()
    stub(Proxy, :call_hoisted_tool, fn _, _, _ -> :not_proxy_tool end)

    Server.handle_message(agent_conn(user), %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/call",
      "params" => %{
        "name" => "create_my_gmail_draft",
        "arguments" => %{"to" => ["lawyer@example.com"], "subject" => "Settlement", "body" => "Confidential"}
      }
    })

    activity = Repo.get_by!(Activity, action: "mcp.tool_called", actor_id: user.id)
    assert activity.metadata["arguments"] == %{}
  end

  defp draft_payload(subject, body, opts \\ []) do
    headers =
      [
        %{"name" => "To", "value" => "anna@example.com"},
        %{"name" => "Cc", "value" => "ben@example.org"},
        %{"name" => "Subject", "value" => subject}
      ] ++
        if(reply = opts[:in_reply_to], do: [%{"name" => "In-Reply-To", "value" => reply}], else: [])

    %{
      "id" => "draft-1",
      "message" => %{
        "id" => "msg-1",
        "threadId" => "thread-1",
        "payload" => %{
          "mimeType" => "text/plain",
          "headers" => headers,
          "body" => %{"data" => Base.url_encode64(body)}
        }
      }
    }
  end

  defp send_gmail do
    gmail(fn
      "GET", "/gmail/v1/users/me/drafts/draft-1", conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer own-token"]
        Req.Test.json(conn, Process.get(:draft))

      "POST", "/gmail/v1/users/me/drafts/send", conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer own-token"]
        assert json_body(conn) == %{"id" => "draft-1"}
        send(self(), :sent)
        Req.Test.json(conn, %{"id" => "sent-1", "threadId" => "thread-1"})
    end)
  end

  defp gmail(handler) do
    stub(Req, :request, fn opts ->
      plug = fn conn -> handler.(conn.method, conn.request_path, Plug.Conn.fetch_query_params(conn)) end
      Req.request(Req.new(Keyword.put(opts, :plug, plug)), [])
    end)
  end

  defp json_body(conn) do
    {:ok, body, _conn} = Plug.Conn.read_body(conn)
    JSON.decode!(body)
  end

  # Gmail's multipart upload carries the Draft resource as JSON, then the
  # message. Returns the resource with the message as `raw`, as Gmail stores it.
  defp uploaded(conn) do
    assert conn.query_params["uploadType"] == "multipart"
    [content_type] = Plug.Conn.get_req_header(conn, "content-type")
    [_, boundary] = Regex.run(~r/\Amultipart\/related; boundary=(\S+)\z/, content_type)
    {:ok, body, _conn} = Plug.Conn.read_body(conn, length: 50_000_000)
    ["", json, message, "--\r\n"] = String.split(body, "--" <> boundary)
    ["\r\nContent-Type: application/json; charset=UTF-8", json] = String.split(json, "\r\n\r\n", parts: 2)
    ["\r\nContent-Type: message/rfc822", message] = String.split(message, "\r\n\r\n", parts: 2)

    json
    |> JSON.decode!()
    |> put_in(["message", "raw"], Base.url_encode64(String.replace_suffix(message, "\r\n", ""), padding: false))
  end

  # A minimal RFC 5322 reader for the messages Atlas writes: headers, then the
  # decoded body or, for multipart content, each part read the same way.
  defp parse(raw), do: raw |> Base.url_decode64!(padding: false) |> mime()

  defp mime(entity) do
    [head, body] = String.split(entity, "\r\n\r\n", parts: 2)

    headers =
      head
      |> String.replace("\r\n ", " ")
      |> String.split("\r\n")
      |> Map.new(fn line ->
        [name, value] = String.split(line, ": ", parts: 2)
        {String.downcase(name), value}
      end)

    case Regex.run(~r/\Amultipart\/\w+; boundary="([^"]+)"\z/, headers["content-type"]) do
      [_, boundary] ->
        ["" | parts] = String.split(body, "--" <> boundary)
        {parts, ["--\r\n"]} = Enum.split(parts, -1)
        {headers, Enum.map(parts, &(&1 |> String.replace_prefix("\r\n", "") |> mime()))}

      nil ->
        {headers, body |> String.replace("\r\n", "") |> Base.decode64!()}
    end
  end

  defp decode_words(value) do
    ~r/=\?UTF-8\?B\?([^?]+)\?=/
    |> Regex.scan(value)
    |> Enum.map_join(fn [_, encoded] -> Base.decode64!(encoded) end)
  end

  defp agent_conn(user), do: %{assigns: %{current_user: user, audit_interface: "mcp"}}

  defp insert_google!(scopes, user_attrs \\ %{}) do
    user = insert_user!(user_attrs)

    %Connection{user_id: user.id, provider: "google"}
    |> Connection.changeset(%{
      provider_user_id: "google-#{user.id}",
      account_name: user.email,
      access_token: "own-token",
      refresh_token: "refresh",
      scopes: scopes
    })
    |> Repo.insert!()

    user
  end
end
