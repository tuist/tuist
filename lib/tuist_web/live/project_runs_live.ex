defmodule TuistWeb.ProjectRunsLive do
  use TuistWeb, :live_view

  alias Tuist.Projects
  alias Tuist.CommandEvents

  def mount(params, _session, %{assigns: %{selected_project: project}} = socket) do
    uri =
      ("?" <> URI.encode_query(Map.take(params, ["after", "before"])))
      |> URI.new!()

    {command_events, command_events_meta} =
      list_command_events(project.id, first: 20)

    slug = Projects.get_project_slug_from_id(project.id)

    {
      :ok,
      socket
      |> assign(:uri, uri)
      |> assign(:page_title, "#{gettext("Runs")} · #{slug} · Tuist")
      |> assign(
        :command_events,
        command_events
      )
      |> assign(
        :command_events_meta,
        command_events_meta
      )
    }
  end

  def handle_event("navigate_to_command_event_detail", _params, socket) do
    {:noreply, push_patch(socket, to: "/command_events/1")}
  end

  def handle_params(params, _uri, %{assigns: %{selected_project: project}} = socket) do
    {next_command_events, next_command_events_meta} =
      cond do
        !is_nil(params["after"]) ->
          list_command_events(project.id, first: 20, after: params["after"])

        !is_nil(params["before"]) ->
          list_command_events(project.id, last: 20, before: params["before"])

        true ->
          list_command_events(project.id, first: 20)
      end

    {
      :noreply,
      socket
      |> assign(
        :command_events,
        next_command_events
      )
      |> assign(
        :command_events_meta,
        next_command_events_meta
      )
    }
  end

  attr(:command_event, :any, required: true)
  slot(:inner_block, required: true)

  def command_event_run_link(assigns) do
    ~H"""
    <.link href={"runs/#{@command_event.id}"}>
      <%= render_slot(@inner_block) %>
    </.link>
    """
  end

  defp list_command_events(project_id, attrs) do
    options = %{
      filters: [
        %{field: :project_id, op: :==, value: project_id},
        %{field: :name, op: :in, value: ["generate", "test", "build", "cache"]}
      ],
      order_by: [:created_at],
      order_directions: [:desc]
    }

    options =
      cond do
        not is_nil(Keyword.get(attrs, :before)) ->
          options
          |> Map.put(:last, 20)
          |> Map.put(:before, Keyword.get(attrs, :before))

        not is_nil(Keyword.get(attrs, :after)) ->
          options
          |> Map.put(:first, 20)
          |> Map.put(:after, Keyword.get(attrs, :after))

        true ->
          options
          |> Map.put(:first, 20)
      end

    CommandEvents.list_command_events(options)
  end
end
