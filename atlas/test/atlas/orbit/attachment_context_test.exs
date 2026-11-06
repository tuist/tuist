defmodule Atlas.Orbit.AttachmentContextTest do
  use Atlas.DataCase, async: true
  use Mimic

  import Atlas.OrbitFixtures

  alias Atlas.Documents.TextExtractor
  alias Atlas.Orbit
  alias Atlas.Orbit.Agent
  alias Atlas.Orbit.AttachmentContext

  setup do
    user = user_fixture()
    {:ok, thread} = Orbit.create_shared(user, %{"title" => "Context"})
    %{user: user, thread: thread}
  end

  test "uses actual text and image bytes, associates image order and leaves filenames as labels", context do
    %{user: user, thread: thread} = context
    text = attachment_fixture(user, thread, "Actual contents, not a filename")
    image = attachment_fixture(user, thread, png_fixture(), %{"filename" => "claim.txt", "content_type" => "image/png"})
    message = post(user, thread, [text.id, image.id])
    {prompt, [input]} = Agent.input([message], nil, user)
    assert prompt =~ "Actual contents, not a filename"
    assert prompt =~ "Attachment #{image.id}"
    assert prompt =~ "image input 1 follows"
    assert input == %{type: :base64, media_type: "image/png", data: Base.encode64(png_fixture())}
    refute prompt =~ Base.encode64(png_fixture())
  end

  test "PDF context is extracted from bytes using the bounded existing extractor", context do
    %{user: user, thread: thread} = context
    bytes = "%PDF-1.4 actual binary document"

    pdf =
      attachment_fixture(user, thread, bytes, %{"filename" => "misleading.txt", "content_type" => "application/pdf"})

    message = post(user, thread, [pdf.id])
    test_pid = self()

    stub(TextExtractor, :extract_pages, fn path, "application/pdf", "attachment.pdf", opts ->
      send(test_pid, {:extracted, File.read!(path), opts})
      {:ok, [%{content: "Real extracted PDF text"}]}
    end)

    {prompt, []} = Agent.input([message], nil, user)
    assert prompt =~ "Real extracted PDF text"
    assert prompt =~ "at most the first 20 pages; no image/OCR content"
    assert_received {:extracted, ^bytes, [timeout: 5_000, max_pages: 20, max_text_bytes: 1_048_576]}
  end

  test "missing extractor, scanned PDFs and unsupported binaries explicitly say contents were not read", context do
    %{user: user, thread: thread} = context

    pdf =
      attachment_fixture(user, thread, "%PDF-1.4", %{"filename" => "secret.pdf", "content_type" => "application/pdf"})

    binary = attachment_fixture(user, thread, "Not readable", %{"content_type" => "application/octet-stream"})
    message = post(user, thread, [pdf.id, binary.id])

    for result <- [
          {:error, :pdftotext_not_found},
          {:ok, []},
          {:error, :pdf_text_too_large},
          {:error, :pdf_text_extraction_failed}
        ] do
      stub(TextExtractor, :extract_pages, fn _, _, _, _ -> result end)
      {prompt, []} = Agent.input([message], nil, user)
      assert prompt =~ "contents not read (PDF text extraction unavailable"
      assert prompt =~ "contents not read (unsupported format)"
      assert prompt =~ "Do not infer contents from the filename"
      refute prompt =~ "Not readable"
    end
  end

  test "invalid image signatures and binary pretending to be text never become model content", context do
    %{user: user, thread: thread} = context
    image = attachment_fixture(user, thread, "Not an image", %{"content_type" => "image/png"})
    text = attachment_fixture(user, thread, <<255, 0, 254>>, %{"content_type" => "text/plain"})
    message = post(user, thread, [image.id, text.id])
    {prompt, []} = Agent.input([message], nil, user)
    assert prompt =~ "contents not read (invalid image signature)"
    assert prompt =~ "contents not read (not valid UTF-8 text)"
    refute prompt =~ "Not an image"
  end

  test "text limits count UTF-8 bytes and omit older contents once the run budget is exhausted", context do
    %{user: user, thread: thread} = context

    messages =
      for index <- 1..5 do
        attachment = attachment_fixture(user, thread, String.duplicate("e\u0301", 8_000) <> "TAIL-#{index}")
        post(user, thread, [attachment.id])
      end

    {contexts, []} = AttachmentContext.build(messages, user)
    assert contexts[hd(messages).id] =~ "text input budget exceeded"

    for message <- tl(messages) do
      assert contexts[message.id] =~ "[truncated]"
      [_label, excerpt] = String.split(contexts[message.id], ":\n", parts: 2)
      assert byte_size(excerpt) <= 12_000
      assert String.valid?(excerpt)
      refute excerpt =~ "TAIL"
    end
  end

  test "images have one total byte/count budget and prefer the newest messages", context do
    %{user: user, thread: thread} = context

    messages =
      for _ <- 1..5 do
        image = attachment_fixture(user, thread, png_fixture(), %{"content_type" => "image/png"})
        post(user, thread, [image.id])
      end

    {contexts, images} = AttachmentContext.build(messages, user)
    assert length(images) == 4
    assert contexts[hd(messages).id] =~ "image input budget exceeded"

    large_bytes = png_fixture() <> :binary.copy(<<0>>, 3 * 1024 * 1024)
    first = attachment_fixture(user, thread, large_bytes, %{"content_type" => "image/png"})
    second = attachment_fixture(user, thread, large_bytes, %{"content_type" => "image/png"})
    message = post(user, thread, [first.id, second.id])
    {contexts, [input]} = AttachmentContext.build([message], user)
    assert contexts[message.id] =~ "image input budget exceeded"
    assert byte_size(Base.decode64!(input.data)) == byte_size(large_bytes)
  end

  test "removed readers and unavailable objects contribute no contents", %{user: user, thread: thread} do
    image = attachment_fixture(user, thread, png_fixture(), %{"content_type" => "image/png"})
    message = post(user, thread, [image.id])
    {contexts, []} = AttachmentContext.build([message], user_fixture())
    assert contexts[message.id] =~ "contents not read (unavailable)"
  end

  defp post(user, thread, ids) do
    {:ok, message, :created} =
      Orbit.post_message(user, thread, %{
        "client_id" => Ecto.UUID.generate(),
        "attachment_ids" => ids,
        "address_agent" => false
      })

    message
  end
end
