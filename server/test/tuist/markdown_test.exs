defmodule Tuist.MarkdownTest do
  use ExUnit.Case, async: true

  alias Tuist.Markdown

  test "renders markdown and sanitizes unsafe links and elements" do
    html = Markdown.to_html("**safe** [unsafe](javascript:alert(1)) <script>alert(1)</script>")

    assert html =~ "<strong>safe</strong>"
    refute html =~ "javascript:"
    refute html =~ "<script>"
  end
end
