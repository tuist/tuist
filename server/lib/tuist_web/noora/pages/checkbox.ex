defmodule TuistWeb.Noora.Pages.Checkbox do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Checkbox",
    description: "Lets people turn an option on or off as part of a form they confirm separately.",
    components: [{Noora.Checkbox, :checkbox}],
    guidelines: [
      "Write the `label` as the option itself, such as Keep me logged in, so checking the box reads as agreeing to it.",
      "Use `description` for the consequence of the option rather than restating the label.",
      "Use `indeterminate` on a checkbox that controls a group when only some of the group is checked.",
      "Pass `field` to take the id, name, and value from a form field. Add `multiple` when several checkboxes share one field, so the name ends in `[]`.",
      "For a setting that applies as soon as it changes, use a toggle instead. A checkbox suits choices confirmed with a separate action, such as a submit button."
    ]

  example "States", description: "Unchecked, checked, and indeterminate." do
    ~H"""
    <.checkbox id="checkbox-unchecked" label="Keep me logged in" />
    <.checkbox id="checkbox-checked" label="Email me about failed builds" checked />
    <.checkbox id="checkbox-indeterminate" label="Select all targets" indeterminate />
    """
  end

  example "With description", description: "A second line explains what the option changes.", layout: :column do
    ~H"""
    <.checkbox
      id="checkbox-description-flaky"
      label="Mark flaky tests"
      description="Tests that pass and fail on the same commit are flagged in test insights."
    />
    <.checkbox
      id="checkbox-description-slack"
      label="Post build summaries to Slack"
      description="A summary is sent to the project's channel after every build on the default branch."
    />
    """
  end

  example "Disabled" do
    ~H"""
    <.checkbox id="checkbox-disabled-unchecked" label="Keep me logged in" disabled />
    <.checkbox id="checkbox-disabled-checked" label="Email me about failed builds" checked disabled />
    <.checkbox id="checkbox-disabled-indeterminate" label="Select all targets" indeterminate disabled />
    """
  end
end
