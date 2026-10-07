defmodule AtlasWeb.DemoLive do
  use AtlasWeb, :live_view
  use Noora

  alias Atlas.Demo

  def mount(_params, _session, socket) do
    if Demo.enabled?() do
      {:ok, assign(socket, :page_title, gettext("Explore Atlas"))}
    else
      {:ok, redirect(socket, to: ~p"/")}
    end
  end

  def render(assigns) do
    ~H"""
    <div id="atlas-demo" data-part="demo-overview">
      <h1>{gettext("A company operating system, ready to explore")}</h1>
      <p>
        {gettext(
          "Welcome to the fictional Northstar team. Explore how Atlas connects commercial accounts, team tasks, finances, and shared knowledge without signing in."
        )}
      </p>
      <div data-part="demo-journeys">
        <.card title={gettext("Understand a customer")} icon="building">
          <.card_section>
            <p>
              {gettext(
                "Open an account to see its contacts, commercial terms, invoices, and timeline together. Try searching for Helio or filtering by lifecycle."
              )}
            </p>
            <.link id="demo-accounts-link" navigate={~p"/commercial/sales/accounts"}>
              {gettext("Explore accounts")}
            </.link>
          </.card_section>
        </.card>
        <.card title={gettext("Follow the money")} icon="chart_donut_4">
          <.card_section>
            <p>
              {gettext(
                "Inspect cash flow and runway, then break down vendor costs. Change the date range to compare recent months."
              )}
            </p>
            <.link id="demo-finance-link" navigate={~p"/commercial/finance"}>
              {gettext("Explore finance")}
            </.link>
          </.card_section>
        </.card>
        <.card title={gettext("Keep the team aligned")} icon="circle_check">
          <.card_section>
            <p>
              {gettext(
                "Browse account-linked tasks and the notes that explain the team's decisions. Search and filters work just as they do in Atlas."
              )}
            </p>
            <.link id="demo-tasks-link" navigate={~p"/tasks"}>{gettext("Explore tasks")}</.link>
          </.card_section>
        </.card>
      </div>
      <p>
        {gettext(
          "This curated demo is a subset of Atlas. Production also supports integrations, agents, contracts, support, engineering, and other operational workflows."
        )}
        <.link id="demo-docs-link" href="https://atlas.tuist.dev/docs">
          {gettext("Discover more in the documentation")}
        </.link>
      </p>
    </div>
    """
  end
end
