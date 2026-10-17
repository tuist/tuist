defmodule TuistWeb.Docs.MarkdownComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias TuistWeb.Docs.MarkdownComponents

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
    assert [_] = Floki.find(document, ~s([data-part="supported-icon"][title="rust"] svg[fill="currentColor"]))
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
