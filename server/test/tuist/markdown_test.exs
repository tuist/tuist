defmodule Tuist.MarkdownTest do
  use ExUnit.Case, async: true

  alias Tuist.Markdown

  test "renders markdown and sanitizes unsafe links and elements" do
    html = Markdown.to_html("**safe** [unsafe](javascript:alert(1)) <script>alert(1)</script>")

    assert html =~ "<strong>safe</strong>"
    refute html =~ "javascript:"
    refute html =~ "<script>"
  end

  test "escapes the input when markdown rendering fails" do
    html = Markdown.to_html(<<0xFF, "<script>alert(1)</script>">>)

    assert html == <<0xFF, "&lt;script&gt;alert(1)&lt;/script&gt;">>
  end
end
