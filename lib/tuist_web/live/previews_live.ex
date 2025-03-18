defmodule TuistWeb.PreviewsLive do
  alias Tuist.Previews
  use TuistWeb, :live_view

  alias Tuist.Projects
  alias Tuist.CommandEvents

  def mount(params, _session, %{assigns: %{selected_project: project}} = socket) do
    uri =
      ("?" <> URI.encode_query(Map.take(params, ["after", "before"])))
      |> URI.new!()

    {command_events, command_events_meta} =
      list_share_command_events(project.id, first: 20, preload: [:preview])

    slug = Projects.get_project_slug_from_id(project.id)

    {
      :ok,
      socket
      |> assign(:uri, uri)
      |> assign(:head_title, "#{gettext("Previews")} · #{slug} · Tuist")
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

  def handle_params(params, _uri, %{assigns: %{selected_project: project}} = socket) do
    {next_command_events, next_command_events_meta} =
      cond do
        !is_nil(params["after"]) ->
          list_share_command_events(project.id,
            first: 20,
            after: params["after"],
            preload: [:preview]
          )

        !is_nil(params["before"]) ->
          list_share_command_events(project.id,
            last: 20,
            before: params["before"],
            preload: [:preview]
          )

        true ->
          list_share_command_events(project.id, first: 20, preload: [:preview])
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

  defp list_share_command_events(project_id, attrs) do
    options = %{
      filters: [
        %{field: :project_id, op: :==, value: project_id},
        %{field: :preview_id, op: :not_empty, value: true},
        %{field: :name, op: :in, value: ["share"]}
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

    CommandEvents.list_command_events(options, preload: [:preview])
  end

  attr(:preview, :map, required: true)

  def supported_platforms_badges(assigns) do
    ~H"""
    <%= supported_platforms = @preview |> Previews.get_supported_platforms_case_values()
    if is_nil(@preview) or Enum.empty?(supported_platforms) do %>
      <.legacy_badge title={gettext("Unknown")} kind={:neutral}></.legacy_badge>
    <% else %>
      <%= for platform <- supported_platforms do %>
        <.legacy_badge title={platform} kind={:neutral}></.legacy_badge>
      <% end %>
    <% end %>
    """
  end
end
