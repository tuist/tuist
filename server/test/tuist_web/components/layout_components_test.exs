defmodule TuistWeb.Components.LayoutComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias TuistWeb.LayoutComponents

  test "head meta tags render dynamic OG image for public projects" do
    assigns = %{
      selected_account: %{name: "tuist"},
      selected_project: %{name: "tuist", visibility: :public, build_system: :xcode},
      head_title: "Compilation · tuist/tuist · Tuist"
    }

    head_meta_html = render_component(&LayoutComponents.head_meta_meta_tags/1, assigns)
    head_x_html = render_component(&LayoutComponents.head_x_meta_tags/1, assigns)

    og_image = meta_content(head_meta_html, "property", "og:image")
    twitter_image = meta_content(head_x_html, "name", "twitter:image")
    twitter_card = meta_content(head_x_html, "name", "twitter:card")

    assert og_image =~ "/tuist/tuist/og/"
    assert twitter_image == og_image
    assert twitter_card == "summary_large_image"
  end

  test "head meta tags fall back for private projects" do
    assigns = %{
      selected_account: %{name: "tuist"},
      selected_project: %{name: "tuist", visibility: :private, build_system: :xcode},
      head_title: "Compilation · tuist/tuist · Tuist"
    }

    head_meta_html = render_component(&LayoutComponents.head_meta_meta_tags/1, assigns)
    head_x_html = render_component(&LayoutComponents.head_x_meta_tags/1, assigns)

    og_image = meta_content(head_meta_html, "property", "og:image")
    twitter_image = meta_content(head_x_html, "name", "twitter:image")
    twitter_card = meta_content(head_x_html, "name", "twitter:card")

    assert og_image == Tuist.Environment.app_url(path: "/images/open-graph/card.jpeg")
    assert twitter_image == og_image
    assert twitter_card == "summary"
  end

  test "head meta tags prefer explicit image and twitter card" do
    assigns = %{
      head_image: "https://cdn.example.com/my-card.jpg",
      head_twitter_card: "summary",
      head_title: "Custom"
    }

    head_meta_html = render_component(&LayoutComponents.head_meta_meta_tags/1, assigns)
    head_x_html = render_component(&LayoutComponents.head_x_meta_tags/1, assigns)

    assert meta_content(head_meta_html, "property", "og:image") == "https://cdn.example.com/my-card.jpg"
    assert meta_content(head_x_html, "name", "twitter:image") == "https://cdn.example.com/my-card.jpg"
    assert meta_content(head_x_html, "name", "twitter:card") == "summary"
  end

  defp meta_content(html, attr_name, attr_value) do
    html
    |> Floki.parse_document!()
    |> Floki.find(~s(meta[#{attr_name}="#{attr_value}"]))
    |> Floki.attribute("content")
    |> List.first()
  end
end
