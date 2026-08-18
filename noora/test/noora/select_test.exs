defmodule Noora.SelectTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Noora.Select

  test "renders without an optional selected value" do
    html =
      render_component(&Select.select/1, %{
        id: "country",
        label: "Country",
        name: "country"
      })

    assert html =~ ~s(id="country")
    assert html =~ ~s(class="noora-dropdown")
    assert html =~ "Country"
  end
end
