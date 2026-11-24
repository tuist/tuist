defmodule TuistWeb.Noora.Pages.Radio do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Radio",
    description: "Lets people pick exactly one option from a short list.",
    components: [{Noora.Radio, :radio_group}, {Noora.Radio, :radio}],
    guidelines: [
      "Use a radio group when people must see every option to choose well and only one can apply. For more than five or so options, use a select instead.",
      "Give the group a `label` that names what is being chosen, such as Visibility. It renders as the group's legend, which assistive tech reads before each option.",
      "Start with one option selected whenever there is a sensible default. A radio can't be cleared once chosen, so add a None option when making no choice is valid.",
      "Write the options as parallel, short labels. Use `description` for the consequence of an option rather than restating its label.",
      "Pass `field` to take the id, name, and value from a form field. The value submits with the form; react to a change with `phx-change` on the form.",
      "Use `radio` on its own only when the options need a custom layout. Give every radio of the set the same `name`, and wrap them in a `fieldset` with a `legend`.",
      "For options that can be combined, use checkboxes. For a single setting that turns on or off, use a checkbox or a toggle."
    ]

  example "Default" do
    ~H"""
    <.radio_group id="radio-default" name="radio-default" value="private" label="Visibility">
      <:radio value="private" label="Private" />
      <:radio value="public" label="Public" />
    </.radio_group>
    """
  end

  example "Horizontal", description: "A row suits two or three short options." do
    ~H"""
    <.radio_group
      id="radio-horizontal"
      name="radio-horizontal"
      value="week"
      label="Report frequency"
      orientation="horizontal"
    >
      <:radio value="day" label="Daily" />
      <:radio value="week" label="Weekly" />
      <:radio value="month" label="Monthly" />
    </.radio_group>
    """
  end

  example "With description", description: "A second line explains what the option changes." do
    ~H"""
    <.radio_group
      id="radio-description"
      name="radio-description"
      value="members"
      label="Who can upload to the cache"
    >
      <:radio
        value="members"
        label="Members and tokens"
        description="Everyone in the account can upload from their machine, and so can CI."
      />
      <:radio
        value="tokens"
        label="Tokens only"
        description="Only CI uploads, so every cached artifact comes from a trusted build."
      />
    </.radio_group>
    """
  end

  example "Disabled", description: "Disable the whole group, or a single option that doesn't apply." do
    ~H"""
    <.radio_group
      id="radio-disabled"
      name="radio-disabled"
      value="private"
      label="Disabled group"
      disabled
    >
      <:radio value="private" label="Disabled selected" />
      <:radio value="public" label="Disabled" />
    </.radio_group>
    <.radio_group
      id="radio-disabled-option"
      name="radio-disabled-option"
      value="private"
      label="Disabled option"
    >
      <:radio value="private" label="Private" />
      <:radio value="public" label="Public" disabled />
    </.radio_group>
    """
  end

  example "Single radios",
    description: "Radios sharing a name behave as one group, for layouts the group doesn't cover.",
    layout: :list do
    ~H"""
    <.radio id="radio-single-light" name="radio-single" value="light" label="Light" checked />
    <.radio id="radio-single-dark" name="radio-single" value="dark" label="Dark" />
    <.radio id="radio-single-system" name="radio-single" value="system" label="System" />
    """
  end
end
