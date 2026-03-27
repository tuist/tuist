defmodule Noora.CheckboxControl do
  @moduledoc false

  use Phoenix.Component

  import Noora.Icon

  @doc """
  Renders just the checkbox control without label or hook.
  Used internally by other Noora components like dropdown items and checkbox.
  """
  attr(:checked, :boolean, default: false, doc: "Whether the checkbox is checked.")
  attr(:indeterminate, :boolean, default: false, doc: "Whether the checkbox is indeterminate.")
  attr(:rest, :global, doc: "Additional attributes")

  def checkbox_control(assigns) do
    ~H"""
    <div
      class="noora-checkbox-control"
      data-state={
        cond do
          @indeterminate -> "indeterminate"
          @checked -> "checked"
          true -> "unchecked"
        end
      }
      {@rest}
    >
      <div data-part="check"><.check /></div>
      <div data-part="minus"><.minus /></div>
    </div>
    """
  end
end
