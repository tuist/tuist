defmodule Noora.BadgeTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Noora.Badge

  test "renders the default style, color, and size" do
    html = render_component(&Badge.badge/1, %{label: "Available"})

    assert html =~ ~s(class="noora-badge")
    assert html =~ ~s(data-style="fill")
    assert html =~ ~s(data-color="neutral")
    assert html =~ ~s(data-size="small")
    assert html =~ ">Available</span>"
  end
end
