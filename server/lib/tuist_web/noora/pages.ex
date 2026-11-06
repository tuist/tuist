defmodule TuistWeb.Noora.Pages do
  @moduledoc """
  The pages of the Noora documentation, in sidebar order.
  """

  alias TuistWeb.Noora.Pages

  @groups [
    {"Getting started", [Pages.Introduction, Pages.Installation]},
    {"Foundations",
     [
       Pages.Brand,
       Pages.Colors,
       Pages.Typography,
       Pages.Spacing,
       Pages.Radius,
       Pages.Borders
     ]},
    {"Components",
     [
       Pages.Alert,
       Pages.Avatar,
       Pages.Badge,
       Pages.Banner,
       Pages.Breadcrumbs,
       Pages.Button,
       Pages.ButtonGroup,
       Pages.Checkbox,
       Pages.DatePicker,
       Pages.DigitInput,
       Pages.DismissIcon,
       Pages.Dropdown,
       Pages.Filter,
       Pages.HintText,
       Pages.Label,
       Pages.LineDivider,
       Pages.LinkButton,
       Pages.Menu,
       Pages.MiddleTruncate,
       Pages.Modal,
       Pages.NeutralButton,
       Pages.PaginationGroup,
       Pages.Popover,
       Pages.ProgressBar,
       Pages.Select,
       Pages.ShortcutKey,
       Pages.Sidebar,
       Pages.TabMenu,
       Pages.Table,
       Pages.Tag,
       Pages.TextArea,
       Pages.TextDivider,
       Pages.TextInput,
       Pages.Time,
       Pages.Toggle,
       Pages.Tooltip
     ]}
  ]

  def groups, do: @groups

  def all, do: Enum.flat_map(@groups, fn {_name, pages} -> pages end)

  def find(slug), do: Enum.find(all(), &(&1.slug() == slug))

  def introduction, do: Pages.Introduction

  def components, do: @groups |> List.keyfind!("Components", 0) |> elem(1)

  def path(Pages.Introduction), do: "/noora"
  def path(page), do: "/noora/" <> page.slug()

  @doc """
  Returns the pages before and after the given one, for the page footer.
  """
  def neighbors(page) do
    pages = all()
    index = Enum.find_index(pages, &(&1 == page))
    previous = if index > 0, do: Enum.at(pages, index - 1)
    {previous, Enum.at(pages, index + 1)}
  end
end
