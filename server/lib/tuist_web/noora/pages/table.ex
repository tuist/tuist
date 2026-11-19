defmodule TuistWeb.Noora.Pages.Table do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Table",
    description: "Lists records such as builds, test runs, and cache entries in rows and columns.",
    components: [
      {Noora.Table, :table},
      {Noora.Table, :text_cell},
      {Noora.Table, :text_and_description_cell},
      {Noora.Table, :badge_cell},
      {Noora.Table, :status_badge_cell},
      {Noora.Table, :tag_cell},
      {Noora.Table, :time_cell},
      {Noora.Table, :button_cell},
      {Noora.Table, :link_button_cell},
      {Noora.Table, :table_empty_state}
    ],
    guidelines: [
      "Pass the records in `rows` and define each column with a `col` slot. Render one cell component inside every column so spacing and typography stay consistent.",
      "Give each row an `id`, or pass `row_key`. A string `id` becomes the row's DOM id as is, and any other value is prefixed with the table `id`, so keys must be unique on the page.",
      "Use `row_navigate` when a row opens a detail page. The first cell becomes a real link, so people can open it in a new tab.",
      "Expandable rows toggle on the client and need no `handle_event`. Use `expanded_rows` for rows that start open, and `row_toggle` only when the details load from the server.",
      "Pair `sort_order` with `patch` on sortable columns, so the header links to the new order and shows its direction.",
      "Pass an `empty_state` slot with a `table_empty_state` that says what will appear there and when."
    ]

  example "Basic", description: "Text, status, and time cells for a list of recent builds.", layout: :column do
    ~H"""
    <.table
      id="table-basic-recent-builds"
      rows={[
        %{
          id: 1,
          command: "tuist build App",
          status: "success",
          label: "Passed",
          duration: "2m 14s",
          ran_at: ~U[2026-10-20 09:42:00Z]
        },
        %{
          id: 2,
          command: "tuist test AppTests",
          status: "error",
          label: "Failed",
          duration: "4m 51s",
          ran_at: ~U[2026-10-20 08:17:00Z]
        },
        %{
          id: 3,
          command: "tuist build App --configuration Release",
          status: "warning",
          label: "Cancelled",
          duration: "38s",
          ran_at: ~U[2026-10-19 17:05:00Z]
        }
      ]}
    >
      <:col :let={build} label="Command">
        <.text_cell label={build.command} />
      </:col>
      <:col :let={build} label="Status">
        <.status_badge_cell status={build.status} label={build.label} />
      </:col>
      <:col :let={build} label="Duration">
        <.text_cell label={build.duration} />
      </:col>
      <:col :let={build} label="Ran at">
        <.time_cell time={build.ran_at} show_time />
      </:col>
    </.table>
    """
  end

  example "Text cells",
    description:
      "`text_cell` holds a label with an optional icon and sublabel. `text_and_description_cell` adds a second line.",
    layout: :column do
    ~H"""
    <.table
      id="table-text-cells-modules"
      rows={[
        %{id: 1, name: "TuistKit", project: "Tuist", target: "Framework", size: "4.8 MB"},
        %{id: 2, name: "TuistCore", project: "Tuist", target: "Framework", size: "2.1 MB"},
        %{
          id: 3,
          name: "ProjectDescription",
          project: "Tuist",
          target: "Dynamic framework",
          size: "1.3 MB"
        }
      ]}
    >
      <:col :let={module} label="Module">
        <.text_and_description_cell
          label={module.name}
          icon="package"
          description={module.project}
          secondary_description={module.target}
        />
      </:col>
      <:col :let={module} label="Binary size">
        <.text_cell label={module.size} sublabel="(uncompressed)" />
      </:col>
    </.table>
    """
  end

  example "Badges and tags",
    description: "Badge, status badge, and tag cells label each row at a glance.",
    layout: :column do
    ~H"""
    <.table
      id="table-badges-and-tags-previews"
      rows={[
        %{
          id: 1,
          version: "4.12.0",
          platform: "iOS",
          icon: "device_mobile",
          track: "Beta",
          status: "success",
          label: "Ready"
        },
        %{
          id: 2,
          version: "4.12.0",
          platform: "macOS",
          icon: "device_laptop",
          track: "Beta",
          status: "in_progress",
          label: "Processing"
        },
        %{
          id: 3,
          version: "4.11.3",
          platform: "iOS",
          icon: "device_mobile",
          track: "Release",
          status: "error",
          label: "Upload failed"
        }
      ]}
    >
      <:col :let={preview} label="Version">
        <.text_cell label={preview.version} />
      </:col>
      <:col :let={preview} label="Platform">
        <.tag_cell label={preview.platform} icon={preview.icon} />
      </:col>
      <:col :let={preview} label="Track">
        <.badge_cell label={preview.track} color="information" style="light-fill" size="large" />
      </:col>
      <:col :let={preview} label="Status">
        <.status_badge_cell status={preview.status} label={preview.label} />
      </:col>
    </.table>
    """
  end

  example "Actions",
    description: "`button_cell` holds one or more buttons. `link_button_cell` renders a single text action.",
    layout: :column do
    ~H"""
    <.table
      id="table-actions-tokens"
      rows={[
        %{id: 1, name: "ci-main", scope: "Read and write cache"},
        %{id: 2, name: "release-pipeline", scope: "Upload previews"}
      ]}
    >
      <:col :let={token} label="Token">
        <.text_and_description_cell label={token.name} description={token.scope} />
      </:col>
      <:col :let={_token} label="Details">
        <.link_button_cell label="View usage" variant="secondary" underline />
      </:col>
      <:col :let={_token} label="">
        <.button_cell>
          <:button>
            <.button icon_only variant="secondary" size="small" aria-label="Edit token">
              <.pencil />
            </.button>
          </:button>
          <:button>
            <.button icon_only variant="destructive" size="small" aria-label="Revoke token">
              <.trash />
            </.button>
          </:button>
        </.button_cell>
      </:col>
    </.table>
    """
  end

  example "Expandable rows",
    description: "Rows open in place to reveal details without leaving the table.",
    layout: :column do
    ~H"""
    <.table
      id="table-expandable-rows-tasks"
      rows={[
        %{
          id: 1,
          task: "Compile TuistKit",
          status: "success",
          label: "Cache hit",
          details: ["Restored from the remote cache in 1.2s", "Key 6f3a9c1e"]
        },
        %{
          id: 2,
          task: "Compile TuistCore",
          status: "attention",
          label: "Cache miss",
          details: ["Inputs changed in Sources/TuistCore/Graph.swift"]
        },
        %{id: 3, task: "Link Tuist", status: "success", label: "Built", details: []}
      ]}
      row_expandable={fn task -> task.details != [] end}
    >
      <:col :let={task} label="Task">
        <.text_cell label={task.task} />
      </:col>
      <:col :let={task} label="Result">
        <.status_badge_cell status={task.status} label={task.label} />
      </:col>
      <:expanded_content :let={task}>
        <p :for={detail <- task.details}>{detail}</p>
      </:expanded_content>
    </.table>
    """
  end

  example "Sorted column",
    description: "`sort_order` shows the sort direction next to the column label.",
    layout: :column do
    ~H"""
    <.table
      id="table-sorted-column-tests"
      rows={[
        %{id: 1, name: "testCacheWarmsAllTargets", duration: "12.4s"},
        %{id: 2, name: "testGeneratesWorkspace", duration: "3.8s"},
        %{id: 3, name: "testResolvesPackages", duration: "1.1s"}
      ]}
    >
      <:col :let={test} label="Test case">
        <.text_cell label={test.name} />
      </:col>
      <:col :let={test} label="Duration" sort_order="desc">
        <.text_cell label={test.duration} />
      </:col>
    </.table>
    """
  end

  example "Empty state", description: "Shown in place of the rows when `rows` is empty.", layout: :column do
    ~H"""
    <.table id="table-empty-state-flaky-tests" rows={[]}>
      <:col label="Test case"></:col>
      <:col label="Flaky runs"></:col>
      <:empty_state>
        <.table_empty_state
          icon="chart_column"
          title="No flaky tests"
          subtitle="Tests that pass and fail on the same commit appear here."
        />
      </:empty_state>
    </.table>
    """
  end
end
