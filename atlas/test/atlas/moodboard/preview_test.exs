defmodule Atlas.Moodboard.PreviewTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Moodboard.Preview
  alias Atlas.Moodboard.SafeHTTP

  setup :verify_on_exit!

  test "extracts article metadata, resolves relative images and ignores executable/navigation content" do
    preview =
      Preview.from_html(
        """
        <html><head><title>Fallback title</title>
        <meta property="og:title" content="Better &amp; brighter">
        <meta property="og:type" content="article">
        <meta property="og:image" content="../cover.png">
        <meta name="description" content="An essay about design."></head>
        <body><nav>Navigation noise</nav><main><article><h1>Article</h1>
        <p>A thoughtful <strong>reference</strong>.</p><script>stealSecrets()</script>
        <style>body {color:red}</style><iframe src="https://evil.example/"></iframe></article></main></body></html>
        """,
        "https://design.example/blog/post"
      )

    assert preview.kind == "article"
    assert preview.source_title == "Better & brighter"
    assert preview.preview_image_url == "https://design.example/cover.png"
    assert preview.source_description == "An essay about design."
    assert preview.source_text == "Article\n\nA thoughtful reference."
    refute preview.source_text =~ "stealSecrets"
    refute preview.source_text =~ "Navigation"
  end

  test "rejects private and executable metadata URLs and never treats player HTML as video" do
    for url <- [
          "http://example.com/image.png",
          "https://127.0.0.1/secret",
          "https://10.0.0.1/",
          "javascript:alert(1)",
          "data:image/png;base64,foo"
        ] do
      preview =
        Preview.from_html(
          """
          <meta property="og:image" content="#{url}">
          <meta property="og:video" content="https://youtube.com/embed/abc">
          <meta property="og:video:type" content="text/html">
          """,
          "https://design.example/"
        )

      assert preview.preview_image_url == nil
      assert preview.preview_video_url == nil
    end
  end

  test "supports playable Open Graph and HTML videos, not arbitrary embeds" do
    preview =
      Preview.from_html(
        """
        <meta property="og:video:secure_url" content="/demo.mp4">
        <meta property="og:video:type" content="video/mp4">
        """,
        "https://design.example/page"
      )

    assert preview.preview_video_url == "https://design.example/demo.mp4"
    assert preview.kind == "video"
    html = Preview.from_html(~s(<video><source src="/clip.webm" type="video/webm"></video>), "https://design.example/")
    assert html.preview_video_url == "https://design.example/clip.webm"
  end

  test "bounds extracted text and metadata" do
    long = String.duplicate("a", 30_000)

    preview =
      Preview.from_html("<meta property='og:title' content='#{long}'><main>#{long}</main>", "https://design.example/")

    assert String.length(preview.source_title) == 200
    assert String.length(preview.source_text) == 20_000
  end

  test "resolves public X posts using only X's credential-free syndication endpoint" do
    expect(SafeHTTP, :fetch, fn url ->
      uri = URI.parse(url)
      assert uri.host == "cdn.syndication.twimg.com"
      assert URI.decode_query(uri.query)["id"] == "12345"
      {:ok, %{status: 200, body: Jason.encode!(x_post())}}
    end)

    assert {:ok, preview} = Preview.fetch("https://x.com/designer/status/12345/video/1")
    assert preview.preview_video_url == "https://video.twimg.com/low.mp4"
    assert preview.preview_image_url == "https://pbs.twimg.com/poster.jpg"
    assert preview.source_text == "A beautiful interaction"
    assert preview.kind == "video"
  end

  test "supports photos, long-form X text and unavailable or malformed post payloads" do
    photo =
      x_post()
      |> Map.put("mediaDetails", [%{"type" => "photo", "media_url_https" => "https://pbs.twimg.com/photo.jpg"}])
      |> Map.put("note_tweet", %{"text" => "Full long-form post"})

    assert %{kind: "image", source_text: "Full long-form post"} = Preview.from_x_post(photo)
    assert %{kind: "article", preview_video_url: nil} = Preview.from_x_post(Map.delete(x_post(), "mediaDetails"))

    for body <- ["{}", "not json", Jason.encode!(%{"id_str" => "12345", "user" => [], "mediaDetails" => [42]})] do
      stub(SafeHTTP, :fetch, fn _url -> {:ok, %{status: 200, body: body}} end)
      assert {:error, :unavailable} = Preview.fetch("https://twitter.com/designer/status/12345")
    end
  end

  test "recognizes direct media and unsupported pages without downloading media into Atlas" do
    for {type, kind, field} <- [{"image/png", "image", :preview_image_url}, {"video/mp4", "video", :preview_video_url}] do
      stub(SafeHTTP, :fetch, fn url -> {:ok, %{status: 200, headers: [{"content-type", type}], body: "", url: url}} end)
      assert {:ok, preview} = Preview.fetch("https://media.example/file")
      assert preview.kind == kind
      assert preview[field] == "https://media.example/file"
    end

    stub(SafeHTTP, :fetch, fn url ->
      {:ok, %{status: 200, headers: [{"content-type", "application/pdf"}], body: "", url: url}}
    end)

    assert {:error, :unsupported_content} = Preview.fetch("https://design.example/file.pdf")
  end

  test "article images win over inline clips, and only the page title is extracted" do
    preview =
      Preview.from_html(
        """
        <html><head><title>A real title</title><meta property="og:type" content="article">
        <meta property="og:image" content="/cover.png"></head>
        <body><article><video src="/decoration.mp4"></video><p>Content</p></article>
        <svg><title>Close</title></svg></body></html>
        """,
        "https://design.example/"
      )

    assert preview.kind == "article"
    assert preview.preview_image_url == "https://design.example/cover.png"
    assert preview.preview_video_url == nil
    assert preview.source_title == "A real title"

    page =
      Preview.from_html(
        ~s(<meta property="og:image" content="/cover.png"><video src="/background.mp4"></video>),
        "https://design.example/"
      )

    assert page.kind == "link"
    assert page.preview_video_url == nil
  end

  test "remote text and X metadata strip PostgreSQL-incompatible control bytes" do
    stub(SafeHTTP, :fetch, fn url ->
      {:ok, %{status: 200, headers: [{"content-type", "text/plain"}], body: "a\0b\x01c\nnext", url: url}}
    end)

    assert {:ok, %{source_text: "abc\n\nnext"}} = Preview.fetch("https://design.example/plain")
    post = x_post() |> Map.put("text", "A\0B") |> Map.put("user", %{"name" => "C\0D"})
    assert %{source_text: "AB", source_title: "CD on X"} = Preview.from_x_post(post)

    stub(SafeHTTP, :fetch, fn url ->
      {:ok, %{status: 200, headers: [{"content-type", "text/plain"}], body: <<255>>, url: url}}
    end)

    assert {:error, :unavailable} = Preview.fetch("https://design.example/invalid")
  end

  defp x_post do
    %{
      "id_str" => "12345",
      "text" => "A beautiful interaction",
      "user" => %{"name" => "Designer"},
      "mediaDetails" => [
        %{
          "type" => "video",
          "media_url_https" => "https://pbs.twimg.com/poster.jpg",
          "video_info" => %{
            "variants" => [
              %{"content_type" => "application/x-mpegURL", "url" => "https://video.twimg.com/stream.m3u8"},
              %{"content_type" => "video/mp4", "bitrate" => 800_000, "url" => "https://video.twimg.com/high.mp4"},
              %{"content_type" => "video/mp4", "bitrate" => 200_000, "url" => "https://video.twimg.com/low.mp4"}
            ]
          }
        }
      ]
    }
  end
end
