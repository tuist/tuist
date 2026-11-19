defmodule TuistWeb.Noora.Pages.MiddleTruncate do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Middle truncate",
    description: "Shortens text in the middle, keeping its start and end visible.",
    components: [{Noora.MiddleTruncate, :middle_truncate}],
    guidelines: [
      "Use it for strings where both ends matter: schemes, branch and project names, IDs, commit SHAs, and file paths.",
      "Don't use it for prose, descriptions, or headings. End truncation reads better there.",
      "The tail is the last segment after a `-`, `_`, `/`, `.`, or space, or the last 8 characters when there's no separator near the end.",
      "The full text stays in the page, so copying gets all of it, screen readers read all of it, and hovering shows it.",
      "Give it a bounded width, such as a table cell or a menu. Without one there's nothing to truncate.",
      "Don't put it inside another element that truncates with an ellipsis; the two conflict."
    ]

  example "Identifiers",
    description: "Drag the corner of the box to change its width and watch the truncation point move.",
    layout: :column do
    ~H"""
    <div class="noora-docs-resizable">
      <.middle_truncate value="TuistAcceptanceTests-iOS-Simulator-Release" />
      <.middle_truncate value="feature/selective-testing-xcode-project-graph" />
      <.middle_truncate value="northwind_industries-ios-app-v12" />
      <.middle_truncate value="9f8e7d6c5b4a4c3d8e2f1a0b9c8d7e6f5a4b3c2d" />
      <.middle_truncate value="app/routes/projects/settings/members.ex" />
      <.middle_truncate value="ios-app" />
    </div>
    """
  end
end
