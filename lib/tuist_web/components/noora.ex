defmodule TuistWeb.Noora do
  @moduledoc """
  Noora is a Phoenix design system built by Tuist.
  """

  defmacro __using__(_opts) do
    quote do
      import TuistWeb.Noora.Alert
      import TuistWeb.Noora.Avatar
      import TuistWeb.Noora.Badge
      import TuistWeb.Noora.Banner
      import TuistWeb.Noora.Breadcrumbs
      import TuistWeb.Noora.Button
      import TuistWeb.Noora.ButtonGroup
      import TuistWeb.Noora.Card
      import TuistWeb.Noora.Chart
      import TuistWeb.Noora.Checkbox
      import TuistWeb.Noora.DismissIcon
      import TuistWeb.Noora.Dropdown
      import TuistWeb.Noora.Filter
      import TuistWeb.Noora.HintText
      import TuistWeb.Noora.Icon
      import TuistWeb.Noora.Label
      import TuistWeb.Noora.LineDivider
      import TuistWeb.Noora.Modal
      import TuistWeb.Noora.PaginationGroup
      import TuistWeb.Noora.ProgressBar
      import TuistWeb.Noora.Select
      import TuistWeb.Noora.ShortcutKey
      import TuistWeb.Noora.Table
      import TuistWeb.Noora.TabMenu
      import TuistWeb.Noora.Tag
      import TuistWeb.Noora.TextDivider
      import TuistWeb.Noora.TextInput
      import TuistWeb.Noora.Tooltip
    end
  end
end
