defmodule Noora.RadioTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Noora.Radio
  alias Noora.RadioControl

  test "renders a native radio input with its label and description" do
    html =
      render_component(&Radio.radio/1, %{
        id: "visibility-private",
        name: "visibility",
        value: "private",
        label: "Private",
        description: "Only members can see it.",
        checked: true
      })

    assert html =~ ~s(type="radio")
    assert html =~ ~s(id="visibility-private")
    assert html =~ ~s(name="visibility")
    assert html =~ ~s(value="private")
    assert html =~ " checked"
    assert html =~ "Private"
    assert html =~ "Only members can see it."
  end

  test "the control follows the input unless given a state" do
    refute render_component(&RadioControl.radio_control/1, %{}) =~ "data-state"

    assert render_component(&RadioControl.radio_control/1, %{checked: true}) =~
             ~s(data-state="checked")

    assert render_component(&RadioControl.radio_control/1, %{checked: false}) =~
             ~s(data-state="unchecked")
  end

  test "a group names its radios and selects the one matching its value" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Radio.radio_group id="policy" name="policy" value={:tokens} label="Who can upload">
        <:radio value="members" label="Members" />
        <:radio value="tokens" label="Tokens" />
      </Radio.radio_group>
      """)

    assert html =~ "<legend"
    assert html =~ "Who can upload"
    assert html =~ ~s(id="policy-members")
    assert length(String.split(html, ~s(name="policy"))) == 3

    [members, tokens] = html |> String.split("<label") |> tl()
    refute members =~ " checked"
    assert tokens =~ " checked"
  end

  test "a group takes its name and value from a form field" do
    form = to_form(%{"visibility" => "public"}, as: :project)
    assigns = %{form: form}

    html =
      rendered_to_string(~H"""
      <Radio.radio_group field={@form[:visibility]}>
        <:radio value="private" label="Private" />
        <:radio value="public" label="Public" />
      </Radio.radio_group>
      """)

    assert html =~ ~s(name="project[visibility]")
    assert html =~ ~s(id="project_visibility-public")
    [_private, public] = html |> String.split("<label") |> tl()
    assert public =~ " checked"
  end

  test "a disabled group disables its fieldset" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Radio.radio_group name="policy" disabled>
        <:radio value="members" label="Members" />
      </Radio.radio_group>
      """)

    assert html =~ ~r/<fieldset[^>]* disabled/
  end
end
