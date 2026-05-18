defmodule Tuist.Marketing.Changelog.EntryParserTest do
  use ExUnit.Case, async: true

  alias Tuist.Marketing.Changelog.EntryParser

  test "renders changelog markdown to html" do
    contents = """
    ---
    title: Failed Tests in PR Comments
    category: Product
    ---

    Tuist now supports **bold** descriptions.

    ![Failed Tests in PR Comment](/marketing/images/changelog/2026.03.19-failed-tests-pr-comment.png)
    """

    {frontmatter, body} =
      EntryParser.parse("priv/marketing/changelog/2026.03.19-failed-tests-pr-comment.md", contents)

    assert frontmatter["id"] == "2026.03.19-failed-tests-pr-comment"
    assert body =~ "<p>Tuist now supports <strong>bold</strong> descriptions.</p>"

    assert body =~
             ~s(<img src="/marketing/images/changelog/2026.03.19-failed-tests-pr-comment.png" alt="Failed Tests in PR Comment")
  end

  test "keeps thematic breaks in the markdown body" do
    contents = """
    ---
    title: Failed Tests in PR Comments
    category: Product
    ---

    First paragraph.

    ---

    Second paragraph.
    """

    {_frontmatter, body} =
      EntryParser.parse("priv/marketing/changelog/2026.03.19-failed-tests-pr-comment.md", contents)

    assert body =~ "<hr"
    assert body =~ "<p>Second paragraph.</p>"
  end

  test "renders code blocks with the shared code window markup" do
    contents = """
    ---
    title: Share the app track
    category: Product
    ---

    ```bash
    tuist share App --track beta
    ```
    """

    {_frontmatter, body} =
      EntryParser.parse("priv/marketing/changelog/2026.03.19-failed-tests-pr-comment.md", contents)

    parsed = Floki.parse_document!(body)

    [code_window] = Floki.find(parsed, ".code-window")
    [bar] = Floki.find(code_window, "[data-part=bar]")
    [language] = Floki.find(bar, "[data-part=language]")
    assert Floki.text(language) == "bash"

    [copy] = Floki.find(bar, "[data-part=copy]")
    assert Floki.find(copy, "[data-part=copy-icon]") != []
    assert Floki.find(copy, "[data-part=copy-check-icon]") != []

    assert Floki.find(code_window, "[data-part=code]") != []
  end
end
