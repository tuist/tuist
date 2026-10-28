defmodule Noora.SelectTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Noora.Select

  test "exposes form-field values to the select machine" do
    form = Phoenix.Component.to_form(%{"language" => "javascript"}, as: :automation)

    html =
      render_component(&Select.select/1, %{
        id: "language",
        label: "Language",
        field: form[:language],
        item: [%{value: "json", label: "JSON"}, %{value: "javascript", label: "JavaScript"}]
      })

    assert html =~ ~s(data-value="javascript")
    assert html =~ ~s(name="automation[language]")
    assert html =~ "JavaScript"
  end

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
