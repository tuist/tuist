defmodule Noora.CheckboxTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Noora.Checkbox

  test "renders without an optional name" do
    html =
      render_component(&Checkbox.checkbox/1, %{
        id: "notifications",
        label: "Enable notifications"
      })

    assert html =~ ~s(id="notifications")
    assert html =~ ~s(class="noora-checkbox")
    assert html =~ "Enable notifications"
  end

  test "renders an explicitly checked state" do
    html =
      render_component(&Checkbox.checkbox/1, %{
        id: "email-alerts",
        label: "Email alerts",
        checked: true
      })

    assert html =~ ~s(data-state="checked")
    assert html =~ ~s(data-default-checked)
    refute html =~ ~s(class="noora-checkbox" checked)
  end

  test "value remains the boolean checked state for hydration" do
    for value <- [true, false] do
      html =
        render_component(&Checkbox.checkbox/1, %{
          id: "remember-me",
          name: "user[remember_me]",
          label: "Keep me logged in",
          value: value
        })

      assert html =~ ~s(data-default-checked) == value
      assert html =~ ~s(name="user[remember_me]")
    end
  end
end
