defmodule TuistWeb.Docs.MarkdownComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias TuistWeb.Docs.MarkdownComponents

  test "Struo and legacy Once support slugs reuse the existing icon" do
    html =
      render_component(&MarkdownComponents.home_card/1,
        title: "Cache",
        details: "Share action results.",
        link: "/guides/features/cache/struo",
        supported_for: "struo,once"
      )

    document = Floki.parse_fragment!(html)
    logo = Floki.parse_fragment!(render_component(&Noora.Icon.brand_once/1, %{}))
    assert Floki.attribute(document, ~s([data-part="supported-icon"]), "title") == ~w(struo once)

    for system <- ~w(struo once) do
      assert Floki.attribute(document, ~s([title="#{system}"] svg path), "d") ==
               Floki.attribute(logo, "path", "d")
    end
  end

  test "home cards render all supported system logos, including Elixir and Rust" do
    html =
      render_component(&MarkdownComponents.home_card/1,
        title: "Insights",
        details: "Track build performance.",
        link: "/guides/features/build-insights",
        supported_for: "apple, android, gradle, bazel, elixir, rust, unknown"
      )

    {:ok, document} = Floki.parse_document(html)

    assert Floki.attribute(document, ~s([data-part="supported-icon"]), "title") ==
             ~w(apple android gradle bazel elixir rust)

    assert [_] = Floki.find(document, ~s([data-part="supported-icon"][title="elixir"] svg))
    assert [_] = Floki.find(document, ~s([data-part="supported-icon"][title="rust"] svg path[fill="currentColor"]))
  end

  test "home cards omit the support row when no systems are specified" do
    html =
      render_component(&MarkdownComponents.home_card/1,
        title: "Insights",
        details: "Track build performance.",
        link: "/guides/features/build-insights"
      )

    refute html =~ ~s(data-part="supported-for")
  end
end
