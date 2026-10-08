defmodule AtlasWeb.DemoLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

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
      <div data-part="demo-introduction">
        <h1>{gettext("A company operating system, ready to explore")}</h1>
        <p>
          {gettext(
            "Welcome to the fictional Northstar team. Explore how Atlas connects commercial accounts, team tasks, finances, and shared knowledge without signing in."
          )}
        </p>
      </div>
      <div data-part="demo-journeys">
        <.card title={gettext("Understand a customer")} icon="building">
          <.card_section data-part="demo-journey">
            <p>
              {gettext(
                "Open an account to see its contacts, commercial terms, invoices, and timeline together. Try searching for Helio or filtering by lifecycle."
              )}
            </p>
            <.button
              id="demo-accounts-link"
              navigate={~p"/commercial/sales/accounts"}
              label={gettext("Explore accounts")}
              variant="secondary"
              size="medium"
            />
          </.card_section>
        </.card>
        <.card title={gettext("Follow the money")} icon="chart_donut_4">
          <.card_section data-part="demo-journey">
            <p>
              {gettext(
                "Inspect cash flow and runway, then break down vendor costs. Change the date range to compare recent months."
              )}
            </p>
            <.button
              id="demo-finance-link"
              navigate={~p"/commercial/finance"}
              label={gettext("Explore finance")}
              variant="secondary"
              size="medium"
            />
          </.card_section>
        </.card>
        <.card title={gettext("Keep the team aligned")} icon="circle_check">
          <.card_section data-part="demo-journey">
            <p>
              {gettext(
                "Browse account-linked tasks and the notes that explain the team's decisions. Search and filters work just as they do in Atlas."
              )}
            </p>
            <.button
              id="demo-tasks-link"
              navigate={~p"/tasks"}
              label={gettext("Explore tasks")}
              variant="secondary"
              size="medium"
            />
          </.card_section>
        </.card>
      </div>
      <p data-part="demo-footer">
        {gettext(
          "This curated demo is a subset of Atlas. Production also supports integrations, agents, contracts, support, engineering, and other operational workflows."
        )}
        <.link id="demo-docs-link" href="https://atlas.tuist.dev/docs" data-part="demo-text-link">
          {gettext("Discover more in the documentation")}
        </.link>
      </p>
    </div>
    """
  end
end
