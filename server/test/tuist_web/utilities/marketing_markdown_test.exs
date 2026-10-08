defmodule TuistWeb.Utilities.MarketingMarkdownTest do
  use ExUnit.Case, async: true

  alias TuistWeb.Utilities.MarketingMarkdown

  test "covers every marketing landing page with an authored guide" do
    assert MarketingMarkdown.guide_paths() == [
             "/",
             "/about",
             "/blog",
             "/brand",
             "/cache",
             "/changelog",
             "/community",
             "/compute",
             "/customers",
             "/download",
             "/globe",
             "/longevity",
             "/newsletter",
             "/openness",
             "/previews",
             "/pricing",
             "/security",
             "/tests"
           ]

    for path <- MarketingMarkdown.guide_paths() do
      markdown = MarketingMarkdown.get(path)

      assert String.starts_with?(markdown, "# Tuist")
      assert markdown =~ "## Limitations"
      refute markdown =~ "](/"
      refute markdown =~ "<script"
      refute markdown =~ "<html"
    end
  end

  test "links to documentation that exists in the checkout" do
    for path <- MarketingMarkdown.guide_paths(),
        [_match, docs_path] <- Regex.scan(~r{/en/docs-markdown/([^\s)]+)}, MarketingMarkdown.get(path)) do
      # Directory indexes are served without the /index suffix.
      source = Path.expand("../../../priv/docs/en/#{docs_path}", __DIR__)
      assert File.exists?(source <> ".md") or File.exists?(Path.join(source, "index.md")), docs_path
    end
  end

  test "legal and policy pages retain their original source wording" do
    for slug <- [
          "terms",
          "privacy",
          "cookies",
          "imprint",
          "trademark-guidelines",
          "data-processing-addendum",
          "data-act-addendum",
          "service-level-addendum"
        ] do
      source = File.read!(Path.expand("../../../priv/marketing/pages/#{slug}.md", __DIR__))
      [_frontmatter, body] = String.split(source, "\n---\n", parts: 2)

      expected_body =
        Regex.replace(~r/\]\((\/[^\s)]*)\)/, body, fn _match, target ->
          "](" <> Tuist.Environment.app_url(path: target) <> ")"
        end)

      assert String.ends_with?(MarketingMarkdown.get("/" <> slug), expected_body)
    end
  end

  test "original statements remain available when an authored guide overrides them" do
    for path <- ["/community", "/openness", "/longevity", "/security"] do
      source = MarketingMarkdown.source(path)
      assert is_binary(source)
      refute source == MarketingMarkdown.get(path)
      assert MarketingMarkdown.get(path) =~ "/marketing-markdown/source" <> path
    end

    assert MarketingMarkdown.source("/cache") == nil
    assert MarketingMarkdown.source("/AGENTS") == nil
    assert MarketingMarkdown.source("/../pages/terms") == nil
  end

  test "directory guides include bounded links to their current entries" do
    for path <- ["/blog", "/changelog", "/customers", "/newsletter"] do
      markdown = MarketingMarkdown.get(path)
      assert [_guide, catalog] = String.split(markdown, "## Current entries", parts: 2)
      links = Regex.scan(~r/^- \[.+\]\(.+\)$/m, catalog)
      refute links == []
      assert length(links) <= 20
      assert catalog =~ "Accept: text/markdown"
    end
  end

  test "alternate discovery drops query parameters and does not invent guides" do
    assert MarketingMarkdown.alternate_path("/") == "/marketing-markdown"
    assert MarketingMarkdown.alternate_path("/cache?utm_source=agent") == "/marketing-markdown/cache"
    assert MarketingMarkdown.alternate_path("/tests") == "/marketing-markdown/tests"
    assert MarketingMarkdown.alternate_path("/de/cache") == nil
    assert MarketingMarkdown.alternate_path("/newsletter/verify") == nil
    assert MarketingMarkdown.get("/de/cache") == nil
    assert MarketingMarkdown.get("/../pages/terms") == nil
    assert MarketingMarkdown.get("/AGENTS") == nil
  end

  test "documents important feature-specific constraints" do
    assert MarketingMarkdown.get("/compute") =~ "invite-only"
    assert MarketingMarkdown.get("/compute") =~ "Pricing is not public yet"
    assert MarketingMarkdown.get("/tests") =~ "Tuist-generated Xcode projects"
    assert MarketingMarkdown.get("/previews") =~ "device builds must be correctly signed"
    assert MarketingMarkdown.get("/pricing") =~ "does not duplicate numeric rates"
  end
end
