defmodule TuistWeb.Noora.Pages.Sidebar do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Sidebar",
    description: "Lists the main sections of an app in a vertical navigation column.",
    components: [{Noora.Sidebar, :sidebar}, {Noora.Sidebar, :sidebar_group}, {Noora.Sidebar, :sidebar_item}],
    guidelines: [
      "The sidebar is hidden below 1024px wide, so pair it with a navigation that works on small screens.",
      "Mark the item for the current page with `selected`. Groups take `selected` too, for the page their own link points to.",
      "Open the group that contains the current page with `default_open`. Groups remember whether they are open for the rest of the browser session, keyed by their `id`, so keep group ids stable.",
      "Give a group `navigate`, `patch`, or `href` when it has an overview page. Its label then links to that page and a separate chevron toggles the group.",
      "Use `collapsible={false}` for a group that only labels a set of items. Its icon and links are ignored.",
      ~s(Set `external` on items that leave the app, and pass `target="_blank"` and `rel="noopener noreferrer"` with them.)
    ]

  example "Default", description: "Items and collapsible groups for the sections of a project.", layout: :column do
    ~H"""
    <.sidebar id="sidebar-default">
      <.sidebar_item label="Overview" icon="smart_home" navigate="/tuist/tuist" selected />
      <.sidebar_group
        id="sidebar-default-builds"
        label="Builds"
        icon="versions"
        navigate="/tuist/tuist/builds"
        default_open
      >
        <.sidebar_item
          label="Build runs"
          icon="chart_column"
          navigate="/tuist/tuist/builds/build-runs"
        />
      </.sidebar_group>
      <.sidebar_group
        id="sidebar-default-tests"
        label="Tests"
        icon="subtask"
        navigate="/tuist/tuist/tests"
      >
        <.sidebar_item label="Test runs" icon="dashboard" navigate="/tuist/tuist/tests/test-runs" />
        <.sidebar_item label="Test cases" icon="exchange" navigate="/tuist/tuist/tests/test-cases" />
      </.sidebar_group>
      <.sidebar_item label="Previews" icon="devices" navigate="/tuist/tuist/previews" />
      <.sidebar_item label="Bundles" icon="chart_donut_4" navigate="/tuist/tuist/bundles" />
    </.sidebar>
    """
  end

  example "Collapsible groups",
    description:
      "A group with a link has its own page and a chevron to toggle it. Without a link, the whole row toggles the group.",
    layout: :column do
    ~H"""
    <.sidebar id="sidebar-collapsible">
      <.sidebar_group
        id="sidebar-collapsible-runners"
        label="Runners"
        icon="server"
        navigate="/tuist/runners"
        default_open
      >
        <.sidebar_item label="Jobs" icon="subtask" navigate="/tuist/runners/jobs" />
        <.sidebar_item label="Profiles" icon="settings" navigate="/tuist/runners/profiles" />
      </.sidebar_group>
      <.sidebar_group id="sidebar-collapsible-cache" label="Cache" icon="database" default_open>
        <.sidebar_item label="Module cache" icon="database" navigate="/tuist/tuist/module-cache" />
        <.sidebar_item
          label="Cache runs"
          icon="chart_column"
          navigate="/tuist/tuist/module-cache/cache-runs"
        />
      </.sidebar_group>
    </.sidebar>
    """
  end

  example "Static groups",
    description: "A group with `collapsible={false}` labels the items under it.",
    layout: :column do
    ~H"""
    <.sidebar id="sidebar-static">
      <.sidebar_group id="sidebar-static-account" label="Account" icon="users" collapsible={false}>
        <.sidebar_item label="Projects" icon="folders" navigate="/tuist/projects" />
        <.sidebar_item label="Members" icon="users" navigate="/tuist/members" />
        <.sidebar_item label="Billing" icon="credit_card" navigate="/tuist/billing" />
        <.sidebar_item label="Settings" icon="settings" navigate="/tuist/settings" />
      </.sidebar_group>
    </.sidebar>
    """
  end

  example "External links",
    description: "`external` adds an icon that tells people the link leaves the app.",
    layout: :column do
    ~H"""
    <.sidebar id="sidebar-external">
      <.sidebar_item
        label="Documentation"
        icon="book"
        href="https://docs.tuist.dev"
        target="_blank"
        rel="noopener noreferrer"
        external
      />
      <.sidebar_item
        label="Status"
        icon="server"
        href="https://status.tuist.dev"
        target="_blank"
        rel="noopener noreferrer"
        external
      />
    </.sidebar>
    """
  end
end
