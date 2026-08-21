defmodule TuistWeb.OpsKuraRolloutLive do
  @moduledoc """
  Detail page for one Kura rollout: the facts grid, the operator verbs
  while the rollout is non-terminal, its wave progress, and the full
  audit trail with pagination. Terminal rollouts keep their trail
  browsable here — the overview only ever shows the latest rollout.
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.OpsKuraComponents

  alias Tuist.Kura.Rollouts
  alias TuistWeb.Utilities.Query

  @page_size 25

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    rollout = Rollouts.get_rollout(id)

    if is_nil(rollout) do
      raise TuistWeb.Errors.NotFoundError, "Kura rollout not found."
    end

    if connected?(socket) do
      Rollouts.subscribe()
    end

    {:ok,
     socket
     |> assign(:head_title, "Rollout #{rollout.image_tag} · Tuist")
     |> assign(:rollout, rollout)
     |> load_rollout_state()}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    query_params = Query.query_params(uri)
    page = parse_page(query_params["page"])

    {events, meta} = Rollouts.paginate_events(socket.assigns.rollout, page, @page_size)

    {:noreply,
     socket
     |> assign(:query_params, query_params)
     |> assign(:current_page, page)
     |> assign(:events, events)
     |> assign(:events_meta, meta)}
  end

  @impl true
  def handle_info({:kura_rollouts, :updated}, socket) do
    socket = load_rollout_state(socket)

    {events, meta} =
      Rollouts.paginate_events(socket.assigns.rollout, socket.assigns.current_page, @page_size)

    {:noreply,
     socket
     |> assign(:events, events)
     |> assign(:events_meta, meta)}
  end

  @impl true
  def handle_event("operate", %{"action" => action, "reason" => reason}, socket) do
    actor = socket.assigns.current_user.email

    socket =
      case operate(socket.assigns.rollout, action, actor, reason) do
        {:ok, _rollout} ->
          put_flash(socket, :info, "Rollout #{action} applied.")

        {:error, reason} ->
          put_flash(socket, :error, operate_error_message(reason, action))
      end

    socket = load_rollout_state(socket)

    {events, meta} =
      Rollouts.paginate_events(socket.assigns.rollout, socket.assigns.current_page, @page_size)

    {:noreply,
     socket
     |> assign(:events, events)
     |> assign(:events_meta, meta)}
  end

  defp load_rollout_state(socket) do
    rollout = Rollouts.get_rollout(socket.assigns.rollout.id)

    socket
    |> assign(:rollout, rollout)
    |> assign(:waves, Rollouts.wave_summary(rollout))
  end
end
