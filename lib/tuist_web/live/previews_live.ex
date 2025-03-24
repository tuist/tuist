defmodule TuistWeb.PreviewsLive do
  alias Tuist.Previews
  use TuistWeb, :live_view

  alias Tuist.Projects
  alias Tuist.Previews

  def mount(params, _session, %{assigns: %{selected_project: project}} = socket) do
    uri =
      ("?" <> URI.encode_query(Map.take(params, ["after", "before"])))
      |> URI.new!()

    {previews, previews_meta} =
      list_previews(project.id, first: 20)

    slug = Projects.get_project_slug_from_id(project.id)

    {
      :ok,
      socket
      |> assign(:uri, uri)
      |> assign(:head_title, "#{gettext("Previews")} · #{slug} · Tuist")
      |> assign(
        :previews,
        previews
      )
      |> assign(
        :previews,
        previews_meta
      )
    }
  end

  def handle_params(params, _uri, %{assigns: %{selected_project: project}} = socket) do
    {next_previews, next_previews_meta} =
      cond do
        !is_nil(params["after"]) ->
          list_previews(project.id,
            first: 20,
            after: params["after"]
          )

        !is_nil(params["before"]) ->
          list_previews(project.id,
            last: 20,
            before: params["before"]
          )

        true ->
          list_previews(project.id, first: 20)
      end

    {
      :noreply,
      socket
      |> assign(
        :previews,
        next_previews
      )
      |> assign(
        :previews_meta,
        next_previews_meta
      )
    }
  end

  defp list_previews(project_id, attrs) do
    options = %{
      filters: [
        %{field: :project_id, op: :==, value: project_id}
      ],
      order_by: [:inserted_at],
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

    Previews.list_previews(options, preload: [:ran_by_account, command_event: [user: [:account]]])
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
