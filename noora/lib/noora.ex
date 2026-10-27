defmodule Noora do
  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  @external_resource "README.md"

  defmacro __using__(_opts) do
    quote do
      import Noora.Alert
      import Noora.Avatar
      import Noora.Badge
      import Noora.Banner
      import Noora.Breadcrumbs
      import Noora.Button
      import Noora.ButtonDropdown
      import Noora.ButtonGroup
      import Noora.Card
      import Noora.Chart
      import Noora.Checkbox
      import Noora.DatePicker
      import Noora.DismissIcon
      import Noora.Dropdown
      import Noora.Filter
      import Noora.HintText
      import Noora.Icon
      import Noora.Label
      import Noora.LineDivider
      import Noora.Modal
      import Noora.PaginationGroup
      import Noora.Popover
      import Noora.ProgressBar
      import Noora.Select
      import Noora.ShortcutKey
      import Noora.Sidebar
      import Noora.Table
      import Noora.TabMenu
      import Noora.Tag
      import Noora.TextArea
      import Noora.TextDivider
      import Noora.TextInput
      import Noora.Toggle
      import Noora.Tooltip
    end
  end
end
