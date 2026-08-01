defmodule Noora.BadgeTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Noora.Badge

  test "renders defaults from the shared badge contract" do
    html = render_component(&Badge.badge/1, %{label: "Available"})

    assert html =~ ~s(class="noora-badge")
    assert html =~ ~s(data-style="fill")
    assert html =~ ~s(data-color="neutral")
    assert html =~ ~s(data-size="small")
    assert html =~ ">Available</span>"
  end

  test "uses the shared appearance, color, and size values" do
    assert Badge.badge_appearances() == ["fill", "light-fill"]

    assert Badge.badge_colors() == [
             "neutral",
             "destructive",
             "warning",
             "attention",
             "success",
             "information",
             "focus",
             "primary",
             "secondary"
           ]

    assert Badge.badge_sizes() == ["small", "large"]
  end
end
