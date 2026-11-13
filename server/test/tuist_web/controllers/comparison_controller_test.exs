defmodule TuistWeb.Marketing.ComparisonControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  @comparisons [{"develocity", "Develocity"}, {"namespace", "Namespace"}, {"buildkite", "Buildkite"}]
  @definition "Tuist is build infrastructure for engineering teams and coding agents."

  test "featured comparisons render sourced decisions and distinct sharing metadata", %{conn: conn} do
    metadata =
      for {slug, name} <- @comparisons do
        path = "/compare/" <> slug
        document = conn |> get(path <> "?utm_source=comparison") |> html_response(200) |> Floki.parse_document!()
        content = Floki.find(document, "#marketing-comparison [data-part=content]")
        text = Floki.text(content)

        assert text =~ @definition
        headings = content |> Floki.find("h2") |> Enum.map(&Floki.text/1)
        assert "What is #{name}?" in headings
        assert "Choose #{name} when" in headings
        assert "Choose Tuist when" in headings
        assert "Sources and review" in headings
        assert content |> Floki.find("tbody tr") |> length() == 6

        links = Floki.attribute(content, "a", "href")

        for link <- ["/cache", "/tests", "/compute", "/pricing", "/compare", "/en/docs/guides/get-started"] do
          assert link in links
        end

        assert Enum.any?(links, &String.starts_with?(&1, "https://"))
        assert Floki.attribute(document, "link[rel=canonical]", "href") == [Tuist.Environment.app_url(path: path)]
        assert Floki.find(document, "link[hreflang]") == []
        assert Floki.attribute(document, "nav[aria-label=Breadcrumbs] a", "href") == ["/", "/compare"]
        assert Floki.text(Floki.find(document, "[aria-current=page]")) =~ name

        schemas = document |> Floki.find("script[type='application/ld+json']") |> Floki.text(js: true)
        assert schemas =~ "BreadcrumbList"
        refute schemas =~ "FAQPage"
        refute schemas =~ "AggregateRating"

        [title] = Floki.attribute(document, "meta[property='og:title']", "content")
        [description] = Floki.attribute(document, "meta[name=description]", "content")
        [image] = Floki.attribute(document, "meta[property='og:image']", "content")
        {title, description, image}
      end

    for index <- 0..2 do
      values = Enum.map(metadata, &elem(&1, index))
      assert Enum.uniq(values) == values
    end
  end

  test "hub retains existing discovery and comparison Markdown twins", %{conn: conn} do
    hub = conn |> get("/compare") |> html_response(200) |> Floki.parse_document!()
    links = Floki.attribute(hub, "[data-part=content] a", "href")
    refute "/compare/amp" in links

    for {slug, name} <- @comparisons do
      assert ("/compare/" <> slug) in links
      markdown = conn |> get("/marketing-markdown/compare/" <> slug) |> response(200)
      assert markdown =~ "# Tuist vs #{name}:"
      assert markdown =~ @definition
      assert markdown =~ "## Choose #{name} when"
    end

    for slug <-
          ~w(appcircle bitrise blacksmith buildbuddy buildjet circleci cirun codemagic depot runs-on ubicloud warpbuild) do
      assert ("/compare/" <> slug) in links
    end
  end

  test "tool comparisons are discoverable, indexable, and link the docs they depend on", %{conn: conn} do
    hub_links = conn |> get("/compare") |> html_response(200) |> Floki.parse_document!() |> Floki.attribute("a", "href")
    xml = conn |> get("/sitemap.xml") |> response(200)

    for {slug, title, migration_link} <- [
          {"xcodegen", "XcodeGen vs Tuist: keep XcodeGen, add build infrastructure",
           "/en/docs/guides/features/projects/adoption/migrate/xcodegen-project"},
          {"nx", "Nx vs Tuist: monorepo task runner and build infrastructure",
           "/en/docs/guides/features/cache/gradle-cache"}
        ] do
      path = "/compare/" <> slug
      document = conn |> get(path) |> html_response(200) |> Floki.parse_document!()
      content = Floki.find(document, "#marketing-comparison [data-part=content]")

      assert path in hub_links
      assert xml =~ ~r|<loc>#{Regex.escape(Tuist.Environment.app_url(path: path))}</loc>\s*<lastmod>2026-11-12</lastmod>|
      assert document |> Floki.find("h1") |> Floki.text() == title
      assert Floki.text(content) =~ String.trim_trailing(@definition, ".")
      assert migration_link in Floki.attribute(content, "a", "href")
      assert Floki.attribute(document, "link[rel=canonical]", "href") == [Tuist.Environment.app_url(path: path)]
      assert Floki.find(document, "link[hreflang]") == []
      assert Floki.attribute(document, "nav[aria-label=Breadcrumbs] a", "href") == ["/", "/compare"]
    end
  end

  test "sitemap derives the featured English comparison review dates", %{conn: conn} do
    xml = conn |> get("/sitemap.xml") |> response(200)
    refute xml =~ "<loc>#{Tuist.Environment.app_url(path: "/compare/amp")}</loc>"

    for path <- ["/compare" | Enum.map(@comparisons, fn {slug, _name} -> "/compare/" <> slug end)] do
      assert xml =~ ~r|<loc>#{Regex.escape(Tuist.Environment.app_url(path: path))}</loc>\s*<lastmod>2026-11-08</lastmod>|
      refute xml =~ "<loc>#{Tuist.Environment.app_url(path: "/de" <> path)}</loc>"
    end
  end
end
