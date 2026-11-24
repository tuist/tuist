defmodule Noora.BannerTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest

  alias Noora.Banner

  test "renders the title and description without an action" do
    html =
      render_component(&Banner.banner/1, %{id: "notice", status: "success", title: "Saved", description: "All good"})

    assert html =~ ~s(data-part="title">Saved</span>)
    assert html =~ ~s(data-part="description">All good</span>)
    refute html =~ ~s(data-part="action")
  end

  test "renders the action after a separating dot" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Banner.banner id="notice" status="information" title="Tuist 5 is out">
        <:action><a href="/blog">Read more</a></:action>
      </Banner.banner>
      """)

    assert html =~ ~s(data-part="dot")
    assert html =~ ~r/data-part="action">\s*<a href="\/blog">Read more<\/a>/
  end
end
