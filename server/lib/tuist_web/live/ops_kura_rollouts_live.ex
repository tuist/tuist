defmodule TuistWeb.OpsKuraRolloutsLive do
  @moduledoc """
  Paginated history of every Kura rollout in this environment, newest
  first. Rows link to the rollout detail page with the full audit trail.
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.OpsKuraComponents

  alias Tuist.Kura.Rollouts
  alias TuistWeb.Utilities.Query

  @page_size 25

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :head_title, "Kura Rollout History · Tuist")}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    query_params = Query.query_params(uri)
    page = parse_page(query_params["page"])
    {rollouts, meta} = Rollouts.paginate_rollouts(page, @page_size)

    {:noreply,
     socket
     |> assign(:query_params, query_params)
     |> assign(:current_page, page)
     |> assign(:rollouts, rollouts)
     |> assign(:meta, meta)}
  end
end
