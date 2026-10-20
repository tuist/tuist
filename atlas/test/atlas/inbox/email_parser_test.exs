defmodule Atlas.Inbox.EmailParserTest do
  use ExUnit.Case, async: true

  alias Atlas.Inbox.EmailParser

  describe "parse/2 - headers and participants" do
    test "parses headers, participants, date, and plain text body" do
      raw_email = """
      Message-ID: <conversation-123@example.com>
      Date: Thu, 07 May 2026 15:30:00 +0200
      From: "Maya Chen" <maya@acme.example>
      To: Inbox <inbox@atlas.tuist.dev>
      Cc: Nico Alvarez <nico@acme.example>
      Subject: Renewal planning

      Hi team,

      Can we schedule the renewal planning session next week?
      """

      email = EmailParser.parse(raw_email)

      assert email.message_id == "conversation-123@example.com"
      assert email.subject == "Renewal planning"
      assert email.occurred_at == ~U[2026-05-07 13:30:00Z]
      assert email.text_body =~ "renewal planning session"

      assert Enum.map(email.participants, & &1.email) == [
               "inbox@atlas.tuist.dev",
               "maya@acme.example",
               "nico@acme.example"
             ]

      assert hd(email.from).name == "Maya Chen"
      assert email.markdown =~ "**Subject:** Renewal planning"
    end

    test "parses bare email addresses without angle brackets" do
      raw_email = "From: maya@acme.example\nTo: inbox@atlas.tuist.dev\n\nHello"

      email = EmailParser.parse(raw_email)

      assert [%{email: "maya@acme.example", name: nil}] = email.from
      assert [%{email: "inbox@atlas.tuist.dev", name: nil}] = email.to
    end

    test "parses multiple comma-separated addresses" do
      raw_email = "From: a@x.com\nTo: b@x.com, c@x.com\n\nHello"

      email = EmailParser.parse(raw_email)

      assert length(email.to) == 2
      assert Enum.map(email.to, & &1.email) == ["b@x.com", "c@x.com"]
    end

    test "merges roles when the same address appears in multiple fields" do
      raw_email = "From: shared@x.com\nTo: shared@x.com\n\nHello"

      email = EmailParser.parse(raw_email)

      assert [participant] = email.participants
      assert participant.email == "shared@x.com"
      assert Enum.sort(participant.roles) == ["from", "to"]
    end

    test "preserves name from the first field and merges roles" do
      raw_email = "From: Named User <user@x.com>\nTo: user@x.com\n\nHello"

      email = EmailParser.parse(raw_email)

      [p] = email.participants
      assert p.name == "Named User"
      assert "from" in p.roles
      assert "to" in p.roles
    end

    test "strips angle brackets from message-id" do
      raw_email = "Message-ID: <abc-123@example.com>\n\nBody"

      email = EmailParser.parse(raw_email)

      assert email.message_id == "abc-123@example.com"
    end

    test "parses reply threading headers without angle brackets" do
      raw_email = """
      Message-ID: <reply-123@example.com>
      In-Reply-To: <root-123@example.com>
      References: <root-123@example.com> <intermediate-123@example.com>

      Body
      """

      email = EmailParser.parse(raw_email)

      assert email.in_reply_to == "root-123@example.com"
      assert email.references == ["root-123@example.com", "intermediate-123@example.com"]
    end

    test "falls back to envelope from/to when headers are absent" do
      raw_email = "Subject: No headers\n\nBody"

      email = EmailParser.parse(raw_email, %{"from" => "sender@x.com", "to" => "inbox@atlas.tuist.dev"})

      assert [%{email: "sender@x.com"}] = email.from
      assert [%{email: "inbox@atlas.tuist.dev"}] = email.to
    end

    test "stores envelope in parsed struct" do
      envelope = %{"from" => "a@x.com", "to" => "b@x.com"}
      email = EmailParser.parse("Subject: X\n\nBody", envelope)

      assert email.envelope == envelope
    end
  end

  describe "parse/2 - date parsing" do
    test "parses date with +HH:MM offset" do
      raw_email = "Date: Thu, 07 May 2026 15:30:00 +0200\n\nBody"

      assert EmailParser.parse(raw_email).occurred_at == ~U[2026-05-07 13:30:00Z]
    end

    test "parses date without seconds" do
      raw_email = "Date: Thu, 07 May 2026 15:30 +0000\n\nBody"

      assert EmailParser.parse(raw_email).occurred_at == ~U[2026-05-07 15:30:00Z]
    end

    test "parses date without day-of-week prefix" do
      raw_email = "Date: 07 May 2026 15:30:00 +0000\n\nBody"

      assert EmailParser.parse(raw_email).occurred_at == ~U[2026-05-07 15:30:00Z]
    end

    test "parses date with negative UTC offset" do
      raw_email = "Date: 07 May 2026 15:30:00 -0500\n\nBody"

      assert EmailParser.parse(raw_email).occurred_at == ~U[2026-05-07 20:30:00Z]
    end

    test "parses date with GMT timezone name" do
      raw_email = "Date: 07 May 2026 15:30:00 GMT\n\nBody"

      assert EmailParser.parse(raw_email).occurred_at == ~U[2026-05-07 15:30:00Z]
    end

    test "parses date with UTC timezone name" do
      raw_email = "Date: 07 May 2026 15:30:00 UTC\n\nBody"

      assert EmailParser.parse(raw_email).occurred_at == ~U[2026-05-07 15:30:00Z]
    end

    test "parses date with Z timezone suffix" do
      raw_email = "Date: 07 May 2026 15:30:00 Z\n\nBody"

      assert EmailParser.parse(raw_email).occurred_at == ~U[2026-05-07 15:30:00Z]
    end

    test "falls back to current time for an unparseable date" do
      raw_email = "Date: not a date\n\nBody"
      before = DateTime.utc_now() |> DateTime.truncate(:second)

      email = EmailParser.parse(raw_email)

      assert is_struct(email.occurred_at, DateTime)
      assert DateTime.compare(email.occurred_at, before) in [:gt, :eq]
    end

    test "falls back to current time when date header is absent" do
      raw_email = "Subject: No date\n\nBody"
      before = DateTime.utc_now() |> DateTime.truncate(:second)

      email = EmailParser.parse(raw_email)

      assert is_struct(email.occurred_at, DateTime)
      assert DateTime.compare(email.occurred_at, before) in [:gt, :eq]
    end
  end

  describe "parse/2 - body extraction" do
    test "extracts a quoted-printable text part from multipart email" do
      raw_email = """
      From: maya@acme.example
      To: inbox@atlas.tuist.dev
      Subject: Multipart
      Content-Type: multipart/alternative; boundary="abc123"

      --abc123
      Content-Type: text/plain; charset=UTF-8
      Content-Transfer-Encoding: quoted-printable

      Follow-up=20needed=20for=20procurement.
      --abc123
      Content-Type: text/html; charset=UTF-8

      <p>Ignored HTML</p>
      --abc123--
      """

      email = EmailParser.parse(raw_email)

      assert email.text_body == "Follow-up needed for procurement."
    end

    test "falls back to HTML part when no text/plain part exists" do
      raw_email = """
      Content-Type: multipart/alternative; boundary="xyz"

      --xyz
      Content-Type: text/html

      <p>Hello <br/>world</p>
      --xyz--
      """

      email = EmailParser.parse(raw_email)

      assert email.text_body =~ "Hello"
      assert email.text_body =~ "world"
    end

    test "converts html entities to plain text in html body" do
      raw_email = "Content-Type: text/html\n\n<p>Hello &amp; world &lt;3&gt;</p>"

      email = EmailParser.parse(raw_email)

      assert email.text_body == "Hello & world <3>"
    end

    test "excludes styles and scripts when falling back to an html body" do
      raw_email = """
      Content-Type: text/html

      <html>
        <head>
          <style>
            @import url('https://fonts.googleapis.com/css2?family=Encode+Sans');
            body { color: #222; }
          </style>
          <script>alert('not part of the message')</script>
        </head>
        <body><p>Your subscription has been renewed.</p></body>
      </html>
      """

      email = EmailParser.parse(raw_email)

      assert email.text_body == "Your subscription has been renewed."
    end

    test "extracts decoded PDF attachments from multipart email" do
      pdf_body = "%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF\n"
      encoded_pdf = Base.encode64(pdf_body)

      raw_email = """
      From: maya@acme.example
      To: inbox@atlas.tuist.dev
      Subject: Signed agreement
      Content-Type: multipart/mixed; boundary="mixed-boundary"

      --mixed-boundary
      Content-Type: text/plain; charset=UTF-8

      Please see the signed agreement.
      --mixed-boundary
      Content-Type: application/pdf; name="signed-agreement.pdf"
      Content-Disposition: attachment; filename="signed-agreement.pdf"
      Content-Transfer-Encoding: base64

      #{encoded_pdf}
      --mixed-boundary--
      """

      email = EmailParser.parse(raw_email)

      assert email.text_body == "Please see the signed agreement."

      assert [
               %{
                 filename: "signed-agreement.pdf",
                 content_type: "application/pdf",
                 body: ^pdf_body,
                 byte_size: byte_size,
                 checksum_sha256: checksum
               }
             ] = email.attachments

      assert byte_size == byte_size(pdf_body)
      assert checksum == :crypto.hash(:sha256, pdf_body) |> Base.encode16(case: :lower)
      assert [%{filename: "signed-agreement.pdf"}] = EmailParser.pdf_attachments(email)

      assert EmailParser.to_agent_context(email).attachments == [
               %{
                 "filename" => "signed-agreement.pdf",
                 "content_type" => "application/pdf",
                 "byte_size" => byte_size(pdf_body),
                 "checksum_sha256" => checksum
               }
             ]
    end

    test "detects PDF attachments by body magic bytes when metadata is generic" do
      pdf_body = "%PDF-1.4\n%%EOF\n"

      raw_email = """
      Content-Type: multipart/mixed; boundary="mixed-boundary"

      --mixed-boundary
      Content-Type: text/plain

      Body.
      --mixed-boundary
      Content-Type: application/octet-stream; name="contract"
      Content-Disposition: attachment; filename="contract"
      Content-Transfer-Encoding: base64

      #{Base.encode64(pdf_body)}
      --mixed-boundary--
      """

      email = EmailParser.parse(raw_email)

      assert [%{filename: "contract"}] = email.attachments
      assert [%{filename: "contract"}] = EmailParser.pdf_attachments(email)
    end

    test "finds inline parts without a content disposition and rejects empty content identifiers" do
      image_body = "image bytes"
      checksum = :crypto.hash(:sha256, image_body) |> Base.encode16(case: :lower)

      raw_email = """
      Content-Type: multipart/related; boundary="related-boundary"

      --related-boundary
      Content-Type: text/html

      <img src="cid:logo@example.com">
      --related-boundary
      Content-Type: image/png; name="logo.png"
      Content-ID: <logo@example.com>
      Content-Transfer-Encoding: base64

      #{Base.encode64(image_body)}
      --related-boundary--
      """

      assert %{body: ^image_body, filename: "logo.png"} = EmailParser.inline_attachment(raw_email, "logo@example.com")
      assert %{body: ^image_body} = EmailParser.attachment_by_checksum(raw_email, checksum)
      assert is_nil(EmailParser.inline_attachment(raw_email, "<>"))
    end
  end

  describe "email_domain/1" do
    test "extracts domain from an email address" do
      assert EmailParser.email_domain("user@example.com") == "example.com"
    end

    test "lowercases the domain" do
      assert EmailParser.email_domain("USER@Example.COM") == "example.com"
    end

    test "returns nil for an address with no @ sign" do
      assert is_nil(EmailParser.email_domain("notanemail"))
    end
  end

  describe "truncate/2" do
    test "returns the text unchanged when within the limit" do
      assert EmailParser.truncate("short", 100) == "short"
    end

    test "truncates and appends marker when over the limit" do
      result = EmailParser.truncate("abcdef", 3)

      assert result == "abc\n\n[truncated]"
    end

    test "returns nil for nil input" do
      assert is_nil(EmailParser.truncate(nil, 100))
    end
  end

  describe "participant_metadata/1" do
    test "serializes participants to string-keyed maps" do
      participants = [
        %{email: "a@x.com", name: "Alice", roles: ["from"]},
        %{email: "b@x.com", name: nil, roles: ["to"]}
      ]

      assert EmailParser.participant_metadata(participants) == [
               %{"email" => "a@x.com", "name" => "Alice", "roles" => ["from"]},
               %{"email" => "b@x.com", "name" => nil, "roles" => ["to"]}
             ]
    end
  end

  test "preserves inline content identifiers and renders them in the original HTML" do
    raw_email = """
    From: Diana <diana@example.com>
    To: contact@tuist.dev
    Subject: Bank details
    MIME-Version: 1.0
    Content-Type: multipart/related; boundary=atlas-boundary

    --atlas-boundary
    Content-Type: text/plain; charset=UTF-8

    See the screenshot.
    [cid:bank-details@example.com]
    --atlas-boundary
    Content-Type: text/html; charset=UTF-8

    <p>See the screenshot.</p><img src="cid:bank-details@example.com" alt="Bank details">
    --atlas-boundary
    Content-Type: image/png; name=bank-details.png
    Content-Disposition: inline; filename=bank-details.png
    Content-ID: <bank-details@example.com>
    Content-Transfer-Encoding: base64

    aW1hZ2UgYnl0ZXM=
    --atlas-boundary--
    """

    parsed = EmailParser.parse(raw_email)

    assert [%{content_id: "bank-details@example.com", filename: "bank-details.png"}] = parsed.attachments

    assert %{body: "image bytes", content_type: "image/png", filename: "bank-details.png"} =
             EmailParser.inline_attachment(raw_email, "bank-details@example.com")

    assert EmailParser.original_html(raw_email, fn content_id -> "/attachments/#{content_id}" end) =~
             ~s(src="/attachments/bank-details@example.com")
  end
end
