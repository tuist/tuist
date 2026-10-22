defmodule Noora.TextAreaTest do
  use ExUnit.Case, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest

  alias Noora.TextArea

  test "omits an overlay unless supplied" do
    html = render_component(&TextArea.text_area/1, id: "plain", name: "plain", value: "Native editing")
    assert html =~ "Native editing"
    refute html =~ ~s(data-part="overlay")
  end

  test "renders an optional overlay as hidden, inert decoration without changing the textarea" do
    html = render_component(&with_overlay/1, %{})
    assert html =~ ~s(data-part="overlay" aria-hidden="true" inert hidden)
    assert html =~ "Highlighted content"
    assert html =~ ~s(name="claims")
    assert html =~ ">{&quot;sub&quot;:&quot;production&quot;}</textarea>"
  end

  defp with_overlay(assigns) do
    ~H"""
    <TextArea.text_area id="claims" name="claims" value={~s({"sub":"production"})}>
      <:overlay>Highlighted content</:overlay>
    </TextArea.text_area>
    """
  end
end
