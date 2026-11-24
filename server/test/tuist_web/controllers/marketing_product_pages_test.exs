defmodule TuistWeb.Marketing.MarketingProductPagesTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  test "product copy preserves designed sections and matching social metadata", %{conn: conn} do
    pages =
      for path <- ["/cache", "/tests", "/runners", "/solutions/slow-builds"] do
        html = conn |> get(path) |> html_response(200) |> Floki.parse_document!()
        main = Floki.find(html, "main")
        text = Floki.text(main)

        assert length(Floki.find(main, "h1")) == 1
        assert text =~ "Tuist is build infrastructure for engineering teams and coding agents"

        if path == "/solutions/slow-builds" do
          for question <- [
                "What is Tuist?",
                "Does this replace CI?",
                "Can we adopt it incrementally?",
                "Hosted or self-hosted?",
                "How do we measure value?"
              ] do
            assert main |> Floki.find("h3") |> Floki.text() =~ question
          end

          assert main |> Floki.find("table") |> Floki.text() =~ "Do nothing"
          assert main |> Floki.find("table") |> Floki.text() =~ "Optimization suite"
        else
          # Logo strip, features, and CTA.
          assert length(Floki.find(html, "main > section")) == 3
        end

        title = html |> Floki.find("title") |> Floki.text() |> String.trim()
        description = html |> Floki.find("meta[name='description']") |> Floki.attribute("content")
        assert description != []
        assert Floki.attribute(Floki.find(html, "meta[property='og:title']"), "content") == [title]
        assert Floki.attribute(Floki.find(html, "meta[property='og:description']"), "content") == description
        {title, description}
      end

    assert length(Enum.uniq_by(pages, &elem(&1, 0))) == 4
    assert length(Enum.uniq_by(pages, &elem(&1, 1))) == 4
  end

  test "feature hubs link every sub-page from the logo strip below their hero", %{conn: conn} do
    for {path, count} <- [{"/cache", 5}, {"/tests", 5}, {"/runners", 3}] do
      links =
        conn
        |> get(path)
        |> html_response(200)
        |> Floki.parse_document!()
        |> Floki.find("main > [data-part=logo-strip] a")
        |> Floki.attribute("href")

      assert length(links) == count, path

      for link <- links do
        assert conn |> get(link) |> html_response(200), link
      end
    end

    # Bitrise is a supported provider without a page of its own.
    strip = conn |> get("/runners") |> html_response(200) |> Floki.parse_document!()
    assert [_, _, _, bitrise] = Floki.find(strip, "main > [data-part=logo-strip] [data-part=logo]")
    assert Floki.text(bitrise) =~ "Bitrise"
    assert Floki.attribute(bitrise, "href") == []
  end
end
