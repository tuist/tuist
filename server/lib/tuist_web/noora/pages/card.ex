defmodule TuistWeb.Noora.Pages.Card do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Card",
    description:
      "Groups related content under a titled header, with optional actions, so a page reads as distinct sections.",
    components: [{Noora.Card, :card}, {Noora.Card, :card_section}],
    guidelines: [
      "Name the card after what it holds, in a few words: Run details, Failures, Quarantined tests.",
      "Pass `icon` as the name of a Noora icon, such as `chart_arcs` or `database`. The card renders it next to the title.",
      "Put the content in one or more `card_section`s. Each section is its own inset panel, so split content that people read separately.",
      "Keep header actions secondary, usually a `secondary` button of size `medium`. On narrow screens they move below the title.",
      "The card fills the width of its container. Size it with the layout around it, such as a grid of cards."
    ]

  example "Default", layout: :column do
    ~H"""
    <.card icon="chart_arcs" title="Run details">
      <.card_section>
        <p>The test run finished in 4m 12s. 1,284 tests passed and 3 were skipped.</p>
      </.card_section>
    </.card>
    """
  end

  example "With actions", description: "Actions sit to the right of the title.", layout: :column do
    ~H"""
    <.card icon="file_zip" title="Logs">
      <:actions>
        <.button label="Download logs" variant="secondary" size="medium" />
      </:actions>
      <.card_section>
        <p>Logs are kept for 30 days after the job finishes.</p>
      </.card_section>
    </.card>
    <.card icon="lock" title="Quarantined tests">
      <:actions>
        <.button label="Export" variant="secondary" size="medium" />
        <.button label="Unquarantine all" variant="secondary" size="medium" />
      </:actions>
      <.card_section>
        <p>12 tests are quarantined. Their failures do not fail the build.</p>
      </.card_section>
    </.card>
    """
  end

  example "Multiple sections", description: "Each section is a separate panel inside the card.", layout: :column do
    ~H"""
    <.card icon="database" title="Cache">
      <.card_section>
        <p>Hit rate: 87% across the last 1,240 builds.</p>
      </.card_section>
      <.card_section>
        <p>Storage used: 18.4 GB of binaries and selective testing results.</p>
      </.card_section>
    </.card>
    """
  end
end
