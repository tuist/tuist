defmodule TuistWeb.Noora.Pages do
  @moduledoc """
  The pages of the Noora documentation, in sidebar order.
  """

  alias TuistWeb.Noora.Pages

  # Pages for working on Noora itself. Every other page is public; these are
  # for the Tuist team, signed in with their tuist.dev account.
  @team_groups [{"Development", [Pages.Icons]}]
  @team_pages Enum.flat_map(@team_groups, fn {_name, pages} -> pages end)

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
       Pages.PaginationGroup,
       Pages.Popover,
       Pages.ProgressBar,
       Pages.Radio,
       Pages.Select,
       Pages.ShortcutKey,
       Pages.Sidebar,
       Pages.Spinner,
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

  # Components brought in line with the new Figma designs, marked with a
  # green dot in the sidebar for the Tuist team (`team_member?/1`). Add a page
  # here once its component is redesigned.
  @redesigned_pages [
    # https://github.com/tuist/tuist/pull/15768
    Pages.Alert,
    Pages.Avatar,
    Pages.Badge,
    Pages.Banner,
    Pages.Breadcrumbs,
    Pages.Button,
    Pages.ButtonGroup,
    Pages.Checkbox,
    Pages.Menu,
    Pages.MiddleTruncate,
    Pages.Radio,
    Pages.Spinner,
    Pages.Toggle
  ]

  @doc """
  Whether the page's component matches the new designs, shown in the sidebar.
  """
  def redesigned?(page), do: page in @redesigned_pages

  @doc """
  The sidebar groups the user can see: the public ones, plus the team's own
  when the user is on the Tuist team.
  """
  def groups(user \\ nil) do
    if team_member?(user), do: @groups ++ @team_groups, else: @groups
  end

  @doc """
  The public pages.
  """
  def all, do: Enum.flat_map(@groups, fn {_name, pages} -> pages end)

  @doc """
  Finds a page by its slug, the team's pages included.
  """
  def find(slug), do: Enum.find(all() ++ @team_pages, &(&1.slug() == slug))

  @doc """
  Whether only the Tuist team can open the page.
  """
  def team_only?(page), do: page in @team_pages

  @doc """
  Whether the user is on the Tuist team: signed in with a tuist.dev account
  that `Tuist.Accounts.tuist_operator?/1` accepts.
  """
  def team_member?(nil), do: false
  def team_member?(user), do: Tuist.Accounts.tuist_operator?(user)

  def introduction, do: Pages.Introduction

  def components, do: @groups |> List.keyfind!("Components", 0) |> elem(1)

  def path(Pages.Introduction), do: "/noora"
  def path(page), do: "/noora/" <> page.slug()

  @doc """
  Returns the pages before and after the given one, for the page footer.
  """
  def neighbors(page, user \\ nil) do
    pages = Enum.flat_map(groups(user), fn {_name, pages} -> pages end)
    index = Enum.find_index(pages, &(&1 == page))
    previous = if index > 0, do: Enum.at(pages, index - 1)
    {previous, Enum.at(pages, index + 1)}
  end
end
