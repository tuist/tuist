defmodule TuistWeb.Noora.Pages.StatusBadge do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Status badge",
    description: "Shows the state of a build, test run, or job with a consistent icon and color.",
    components: [{Noora.Badge, :status_badge}],
    guidelines: [
      "Map each outcome to the same status everywhere: `success` for passed, `error` for failed, `warning` for cancelled, `in_progress` for running.",
      "The status sets the icon and its color, and `disabled` also mutes the label. Write the label for the outcome, such as Passed or Failed.",
      "Use `type=\"dot\"` in dense lists where the icons would compete with the content.",
      "Inside tables, use the table's `status_badge_cell`. It takes the same `status` and `label` but no `type`.",
      "For categories and other labels that are not states, use a badge."
    ]

  example "Statuses", description: "Each status has its own icon." do
    ~H"""
    <.status_badge status="success" label="Passed" />
    <.status_badge status="error" label="Failed" />
    <.status_badge status="warning" label="Cancelled" />
    <.status_badge status="attention" label="Flaky" />
    <.status_badge status="in_progress" label="Running" />
    <.status_badge status="disabled" label="Skipped" />
    """
  end

  example "Dot", description: "`type=\"dot\"` replaces the icon with a dot in the status color." do
    ~H"""
    <.status_badge type="dot" status="success" label="Passed" />
    <.status_badge type="dot" status="error" label="Failed" />
    <.status_badge type="dot" status="warning" label="Cancelled" />
    <.status_badge type="dot" status="attention" label="Flaky" />
    <.status_badge type="dot" status="in_progress" label="Running" />
    <.status_badge type="dot" status="disabled" label="Skipped" />
    """
  end

  example "In a table", description: "Tables use `status_badge_cell`, which renders the same badge.", layout: :column do
    ~H"""
    <.table
      id="status-badge-table-test-runs"
      rows={[
        %{id: 1, scheme: "TuistKitTests", status: "success", label: "Passed"},
        %{id: 2, scheme: "TuistCoreTests", status: "error", label: "Failed"},
        %{id: 3, scheme: "TuistAcceptanceTests", status: "in_progress", label: "Running"}
      ]}
    >
      <:col :let={run} label="Scheme">
        <.text_cell label={run.scheme} />
      </:col>
      <:col :let={run} label="Status">
        <.status_badge_cell status={run.status} label={run.label} />
      </:col>
    </.table>
    """
  end
end
