defmodule AtlasWeb.CodeBlockTest do
  use ExUnit.Case, async: true
  use Mimic

  import Phoenix.LiveViewTest

  alias AtlasWeb.CodeBlock

  test "highlights JSON with light and dark token colors" do
    source = ~s({"enabled": true, "count": 2})
    html = render_component(&CodeBlock.code_block/1, source: source)
    assert html =~ ~s(data-language="json")
    assert html =~ "language-json"
    assert html =~ "color: light-dark("
    assert html =~ "<span"
    assert html |> LazyHTML.from_fragment() |> LazyHTML.query("code") |> LazyHTML.text() |> String.trim() == source
  end

  test "highlights JavaScript without interpreting markup in source strings" do
    source = ~S|const message = "<script>alert('unsafe')</script>"; return {message};|
    html = render_component(&CodeBlock.code_block/1, source: source, language: "javascript")
    assert html =~ "language-javascript"
    assert html =~ "&lt;script&gt;"
    assert html |> LazyHTML.from_fragment() |> LazyHTML.query("script") |> Enum.empty?()
    assert html |> LazyHTML.from_fragment() |> LazyHTML.query("code") |> LazyHTML.text() |> String.trim() == source
  end

  test "keeps malformed drafts readable and escaped" do
    source = ~S|{"value": "<img src=x onerror=alert(1)>",|
    html = render_component(&CodeBlock.code_block/1, source: source)
    assert html =~ "&lt;img"
    assert html |> LazyHTML.from_fragment() |> LazyHTML.query("img") |> Enum.empty?()
    assert html |> LazyHTML.from_fragment() |> LazyHTML.query("code") |> LazyHTML.text() |> String.trim() == source
  end

  test "falls back to escaped plain text if highlighting is unavailable" do
    stub(Lumis, :highlight, fn _, _ -> {:error, "Parser unavailable"} end)
    html = render_component(&CodeBlock.code_block/1, source: "<script>unsafe</script>")
    assert html =~ "&lt;script&gt;unsafe&lt;/script&gt;"
    refute html =~ "<script>"
  end

  test "bounds highlighting work without truncating larger payloads" do
    stub(Lumis, :highlight, fn _, _ -> flunk("Oversized sources must not be highlighted") end)
    source = String.duplicate("x", 262_145)
    html = render_component(&CodeBlock.code_block/1, source: source)
    assert html |> LazyHTML.from_fragment() |> LazyHTML.query("code") |> LazyHTML.text() == source
  end
end
