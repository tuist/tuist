defmodule TuistWeb.Noora.Pages.Menu do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Menu",
    description:
      "A list of actions or links that opens from a trigger. Every trigger opens the same menu, so items look and behave the same everywhere.",
    components: [{Noora.Menu, :menu}, {Noora.Menu, :menu_item}, {Noora.Menu, :menu_separator}],
    guidelines: [
      "Use a menu for actions on one thing, such as a project or a run. Keep it to about ten items.",
      "Write labels as a verb and a noun in sentence case, such as Rename project. Add … only when the item opens a dialog.",
      "Put destructive items last, after a separator, with a specific label such as Delete project.",
      "Give an item either a 16px `icon` or a 20px `image` (an avatar or a logo). Keep leading content consistent within a menu so labels line up.",
      "Use `sublabel` for a short qualifier and `description` for a sentence. A description makes the item two lines tall.",
      "Mark the current choice with `selected`. It shows a check at the end of the item; it highlights like any other item only when hovered or reached with the keyboard.",
      "Use `checked` for options people pick several of, such as visible columns. Items toggle as they're chosen, keep the menu open, and send `on_select` with the new `checked`.",
      "Disable items that aren't available instead of hiding them, so the menu keeps its shape. Keyboard navigation skips them.",
      "Long labels truncate. Use `truncate=\"middle\"` for identifiers such as schemes, branches, and project names, so both ends stay readable; keep the default end truncation for actions."
    ]

  example "Default",
    description: "Choosing an item sends `on_select` with its `value` and closes the menu. Destructive items go last." do
    ~H"""
    <.menu id="menu-default" label="Actions">
      <.menu_item value="rename" label="Rename project" />
      <.menu_item value="duplicate" label="Duplicate project" />
      <.menu_item value="transfer" label="Transfer project…" />
      <.menu_separator />
      <.menu_item value="delete" label="Delete project" variant="destructive" />
    </.menu>
    """
  end

  example "Dots",
    description:
      "`trigger=\"dots\"` opens the menu from a dots button, for overflow actions on a row or card. The `label` names it for screen readers." do
    ~H"""
    <.menu id="menu-dots" label="More actions" trigger="dots">
      <.menu_item value="logs" label="View build logs" />
      <.menu_item value="runs" label="View test runs" />
      <.menu_item value="analytics" label="View analytics" />
    </.menu>
    """
  end

  example "Disabled items",
    description: "Disabled items stay in place and keyboard navigation skips them, including destructive ones." do
    ~H"""
    <.menu id="menu-disabled" label="Manage">
      <.menu_item value="invite" label="Invite member" />
      <.menu_item value="transfer" label="Transfer ownership" sublabel="Admins only" disabled />
      <.menu_separator />
      <.menu_item value="remove" label="Remove member" variant="destructive" disabled />
    </.menu>
    """
  end

  example "Link items", description: "`href`, `navigate`, or `patch` turn an item into a link." do
    ~H"""
    <.menu id="menu-links" label="Help">
      <.menu_item value="docs" label="Documentation" href="https://docs.tuist.dev" target="_blank" />
      <.menu_item value="changelog" label="Changelog" href="#link-items" />
      <.menu_item value="status" label="Status" href="https://status.tuist.dev" target="_blank" />
    </.menu>
    """
  end

  example "Prefix and suffix",
    description: "A 16px `icon` or 20px `image` before the label, and `extra` content such as a badge after it." do
    ~H"""
    <.menu id="menu-prefix-icons" label="Edit">
      <.menu_item value="rename" label="Rename">
        <:icon><.pencil /></:icon>
      </.menu_item>
      <.menu_item value="copy" label="Copy link">
        <:icon><.copy /></:icon>
      </.menu_item>
      <.menu_item value="runners" label="Runners">
        <:icon><.settings /></:icon>
        <:extra><.badge label="New" color="primary" style="light-fill" /></:extra>
      </.menu_item>
    </.menu>
    <.menu id="menu-prefix-images" label="ios-app">
      <.menu_item value="ios-app" label="ios-app" truncate="middle" selected>
        <:image><img src="/images/build-systems/xcode.png" alt="" /></:image>
      </.menu_item>
      <.menu_item value="android-app" label="android-app" truncate="middle">
        <:image><img src="/images/build-systems/gradle.png" alt="" /></:image>
      </.menu_item>
      <.menu_item value="server" label="server" truncate="middle">
        <:image><img src="/images/build-systems/mix.png" alt="" /></:image>
      </.menu_item>
    </.menu>
    """
  end

  example "Shortcuts", description: "Put a shortcut key in `extra` to show how to reach the action from the keyboard." do
    ~H"""
    <.menu id="menu-shortcuts" label="File">
      <.menu_item value="new" label="New project">
        <:extra>
          <.shortcut_key size="small">⌘N</.shortcut_key>
        </:extra>
      </.menu_item>
      <.menu_item value="search" label="Search">
        <:extra>
          <.shortcut_key size="small">⌘K</.shortcut_key>
        </:extra>
      </.menu_item>
      <.menu_item value="settings" label="Settings">
        <:extra>
          <.shortcut_key size="small">⌘,</.shortcut_key>
        </:extra>
      </.menu_item>
    </.menu>
    """
  end

  example "Checkbox items",
    description:
      "`checked` makes an item a checkbox for choosing several options. Items toggle in place and the menu stays open while people toggle.",
    layout: :start do
    ~H"""
    <.menu id="menu-checkboxes" label="Columns">
      <.menu_item value="status" label="Status" checked={true} />
      <.menu_item value="duration" label="Duration" checked={true} />
      <.menu_item value="branch" label="Branch" checked={false} />
      <.menu_item value="ran-by" label="Ran by" checked={false} />
    </.menu>
    <.menu id="menu-checkbox-icons" label="Platforms">
      <.menu_item value="ios" label="iOS" checked={true}>
        <:icon><.device_mobile /></:icon>
      </.menu_item>
      <.menu_item value="macos" label="macOS" checked={false}>
        <:icon><.device_desktop /></:icon>
      </.menu_item>
      <.menu_item value="watchos" label="watchOS" checked={true}>
        <:icon><.device_watch /></:icon>
      </.menu_item>
    </.menu>
    """
  end

  example "Selected",
    description: "`selected` marks the current choice with a check, for menus that pick one option." do
    ~H"""
    <.menu id="menu-selected" label="Last 7 days">
      <.menu_item value="24h" label="Last 24 hours" />
      <.menu_item value="7d" label="Last 7 days" selected />
      <.menu_item value="30d" label="Last 30 days" />
    </.menu>
    """
  end

  example "Descriptions",
    description:
      "A `sublabel` qualifies the label; a `description` adds a second line. With `trigger=\"split\"`, the label runs `on_action` and the chevron opens the menu." do
    ~H"""
    <.menu id="menu-descriptions" label="Copy page" trigger="split" on_action="copy_page">
      <.menu_item value="markdown" label="Copy as Markdown" sublabel="LLMs">
        <:icon><.copy /></:icon>
      </.menu_item>
      <.menu_item
        value="view"
        label="View as Markdown"
        description="Open this page as plain text in a new tab."
      >
        <:icon><.external_link /></:icon>
      </.menu_item>
    </.menu>
    """
  end

  # Dev only: the break-ui stress test. The same menu with demo data, the
  # realistic worst case, and the empty, single, and 1,000-row cases, behind
  # a toggle fixed to the bottom of the page. The data enters through the
  # component's own options; nothing here changes the component. Never
  # compiled outside dev.
  if Mix.env() == :dev do
    alias Phoenix.LiveView.JS

    example "Worst case (dev only)",
      description:
        "Pick the data from the dropdown at the bottom of the page. Worst case also renders in a 320px column.",
      layout: :column do
      ~H"""
      <div id="menu-break" class="noora-docs-break" data-show="demo">
        <div data-state="demo">
          <.menu id="menu-break-demo" label="Release">
            <.break_items items={break_fixture(:demo)} />
          </.menu>
        </div>
        <div data-state="worst">
          <.menu
            id="menu-break-worst"
            label="TuistAcceptanceTests-iOS-Simulator-Release"
          >
            <.break_items items={break_fixture(:worst)} />
          </.menu>
          <div data-part="narrow">
            <.menu
              id="menu-break-worst-narrow"
              label="TuistAcceptanceTests-iOS-Simulator-Release"
            >
              <.break_items items={break_fixture(:worst)} />
            </.menu>
          </div>
        </div>
        <div data-state="empty">
          <.menu id="menu-break-empty" label="None">
            <.break_items items={break_fixture(:empty)} />
          </.menu>
        </div>
        <div data-state="one">
          <.menu id="menu-break-one" label="Release">
            <.break_items items={break_fixture(:one)} />
          </.menu>
        </div>
        <div data-state="many">
          <.menu id="menu-break-many" label="Scheme 1">
            <.break_items items={break_fixture(:many)} />
          </.menu>
        </div>
        <div data-part="toggle">
          <.dropdown id="menu-break-data" label="" secondary_text="Data">
            <.dropdown_item
              :for={
                {value, label} <- [
                  {"demo", "Demo"},
                  {"worst", "Worst case"},
                  {"empty", "Empty"},
                  {"one", "One"},
                  {"many", "1,000 rows"}
                ]
              }
              value={value}
              label={label}
              on_click={JS.set_attribute({"data-show", value}, to: "#menu-break")}
            >
              <:right_icon><.check /></:right_icon>
            </.dropdown_item>
          </.dropdown>
        </div>
      </div>
      """
    end

    defp break_items(assigns) do
      ~H"""
      <.menu_item
        :for={item <- @items}
        value={item.value}
        label={item.label}
        sublabel={item[:sublabel]}
        description={item[:description]}
        variant={item[:variant] || "default"}
        disabled={item[:disabled] || false}
        selected={item[:selected] || false}
        truncate={item[:truncate] || "end"}
      >
        <:image :if={item[:image]}><img src={item.image} alt="" /></:image>
        <:icon :if={item[:icon]}><.icon name={item.icon} /></:icon>
        <:extra :if={item[:shortcut]}>
          <.shortcut_key size="small">{item.shortcut}</.shortcut_key>
        </:extra>
        <:extra :if={item[:badge]}>
          <.badge label={item.badge} color="primary" style="light-fill" />
        </:extra>
      </.menu_item>
      """
    end

    defp break_fixture(:demo) do
      [
        %{value: "release", label: "Release", selected: true},
        %{value: "debug", label: "Debug"},
        %{value: "staging", label: "Staging", sublabel: "Beta"}
      ]
    end

    # Rows spread the failures, as real data does. Project names allow 32
    # characters with no spaces (Tuist.Projects.Project); account names and
    # Xcode schemes have no length limit.
    defp break_fixture(:worst) do
      [
        %{
          value: "scheme",
          label: "TuistAcceptanceTests-iOS-Simulator-Release",
          truncate: "middle",
          selected: true,
          image: "/images/build-systems/xcode.png"
        },
        %{
          value: "project",
          label: "northwind_industries-ios-app-v12",
          truncate: "middle",
          image: "/images/build-systems/gradle.png"
        },
        %{
          value: "settings",
          label: "Benachrichtigungseinstellungen",
          sublabel: "Nur für Administratorinnen und Administratoren",
          icon: "settings"
        },
        %{
          value: "markdown",
          label: "View as Markdown",
          description:
            "Opens https://docs.tuist.dev/en/guides/features/selective-testing/xcode-project?tab=configuration&filter=unresolved in a new tab.",
          icon: "external_link"
        },
        %{value: "j", label: "J"},
        %{value: "dang", label: "Đặng Thị Ngọc Hân"},
        %{value: "nour", label: "نور الهدى عبد الرحمن"},
        %{value: "fox", label: "🦊 Fox workspace"},
        %{value: "runners", label: "Runners", badge: "Invitation expired 12 days ago", shortcut: "⌘⇧⌥K"},
        %{value: "missing", label: "android-app", image: "/images/build-systems/missing.png"},
        %{value: "privacy", label: "Paramètres de confidentialité et de sécurité", disabled: true},
        %{value: "delete", label: "Delete northwind_industries-ios-app-v12", variant: "destructive", icon: "trash"}
      ]
    end

    defp break_fixture(:empty), do: []
    defp break_fixture(:one), do: [%{value: "release", label: "Release", selected: true}]

    defp break_fixture(:many) do
      for i <- 1..1000, do: %{value: "scheme-#{i}", label: "Scheme #{i}", selected: i == 1}
    end
  end
end
