defmodule AtlasWeb.PostmortemLive.Index do
  @moduledoc false

  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Engineering.Postmortems
  alias AtlasWeb.Markdown
  alias Noora.Filter.Filter
  alias Noora.Filter.Operations

  @page_size 20

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, dgettext("postmortems", "Postmortems"))
     |> assign(:available_filters, available_filters())
     |> assign(:active_filters, [])
     |> assign(:uri, URI.parse("/engineering/postmortems"))
     |> assign(:query, "")
     |> assign(:search_form, to_form(%{"query" => ""}, as: :search))
     |> assign(:postmortems, [])
     |> assign(:postmortems_meta, %{current_page: 1, total_pages: 1, total_entries: 0})
     |> assign(:can_publish?, Postmortems.can_publish?(socket.assigns.current_user))}
  end

  @impl true
  def handle_params(params, uri, socket) do
    active_filters =
      Operations.decode_filters_from_query(params, socket.assigns.available_filters)

    query = params |> Map.get("q", "") |> String.trim()
    page = params |> Map.get("page", "1") |> parse_page()

    {postmortems, postmortems_meta} =
      Postmortems.list_postmortems_page(
        page: page,
        page_size: @page_size,
        query: query,
        published: published_filter(active_filters),
        user: socket.assigns.current_user
      )

    {:noreply,
     socket
     |> assign(:uri, URI.parse(uri))
     |> assign(:active_filters, active_filters)
     |> assign(:query, query)
     |> assign(:search_form, to_form(%{"query" => query}, as: :search))
     |> assign(:postmortems, postmortems)
     |> assign(:postmortems_meta, postmortems_meta)}
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    params =
      socket.assigns.active_filters
      |> Operations.encode_filters_to_query()
      |> Map.put("q", String.trim(query))
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
      |> Map.new()

    {:noreply, push_patch(socket, to: ~p"/engineering/postmortems?#{params}", replace: true)}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    params = Operations.add_filter_to_query(filter_id, socket)
    {:noreply, push_patch(socket, to: ~p"/engineering/postmortems?#{params}")}
  end

  def handle_event("update_filter", params, socket) do
    params = Operations.update_filters_in_query(params, socket)
    {:noreply, push_patch(socket, to: ~p"/engineering/postmortems?#{params}")}
  end

  defp available_filters do
    [
      %Filter{
        id: "published",
        field: :published,
        display_name: dgettext("postmortems", "Published"),
        type: :option,
        options: [:last_30_days],
        options_display_names: %{last_30_days: dgettext("postmortems", "Last 30 days")},
        operator: :==,
        value: :last_30_days
      }
    ]
  end

  defp published_filter(active_filters) do
    case Enum.find(active_filters, &(&1.id == "published")) do
      %{operator: :==, value: :last_30_days} -> :last_30_days
      _filter -> nil
    end
  end

  defp parse_page(value) do
    case Integer.parse(value) do
      {page, ""} when page > 0 -> page
      _invalid -> 1
    end
  end

  defp page_link(uri, page) do
    query = URI.decode_query(uri.query || "")
    "?" <> URI.encode_query(Map.put(query, "page", to_string(page)))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="postmortems">
      <div data-part="header">
        <div data-part="title-group">
          <h1>{dgettext("postmortems", "Postmortems")}</h1>
          <p>
            {dgettext("postmortems", "Published accounts of incidents and what we learned from them.")}
          </p>
        </div>
        <div data-part="header-actions">
          <.button
            :if={@can_publish?}
            label={dgettext("postmortems", "Publish postmortem")}
            href={~p"/engineering/postmortems/new"}
            size="medium"
            variant="primary"
          >
            <:icon_left><.circle_plus /></:icon_left>
          </.button>
        </div>
      </div>
      <.card icon="alert_triangle" title={dgettext("postmortems", "Postmortems")}>
        <.card_section>
          <div data-part="table-toolbar">
            <.filter_dropdown
              id="postmortems-filter"
              label={dgettext("postmortems", "Filter")}
              available_filters={@available_filters}
              active_filters={@active_filters}
              on_select="add_filter"
            />
            <div data-part="search">
              <.form
                id="postmortems-search-form"
                for={@search_form}
                phx-change="search"
                phx-submit="search"
              >
                <.text_input
                  id="postmortems-search"
                  field={@search_form[:query]}
                  type="search"
                  show_suffix={false}
                  placeholder={dgettext("postmortems", "Search postmortems...")}
                />
              </.form>
            </div>
          </div>
          <div :if={@active_filters != []} data-part="active-filters">
            <.active_filter :for={filter <- @active_filters} filter={filter} />
          </div>
          <div :if={@postmortems == []} data-part="empty-state">
            <div data-part="empty-icon"><.icon name="alert_triangle" /></div>
            <h2>{dgettext("postmortems", "No postmortems yet")}</h2>
            <p>{dgettext("postmortems", "Published postmortems will appear here.")}</p>
          </div>
          <.table
            :if={@postmortems != []}
            id="postmortems-table"
            rows={@postmortems}
            row_navigate={fn postmortem -> ~p"/engineering/postmortems/#{postmortem.number}" end}
          >
            <:col :let={postmortem} label={dgettext("postmortems", "Postmortem")}>
              <.text_and_description_cell
                label={
                  dgettext("postmortems", "#%{number} %{title}",
                    number: postmortem.number,
                    title: Postmortems.title(postmortem)
                  )
                }
                description={Markdown.preview(postmortem.body)}
                icon="alert_triangle"
              />
            </:col>
            <:col :let={postmortem} label={dgettext("postmortems", "Author")}>
              <div data-part="author-cell">
                <.text_and_description_cell label={author_name(postmortem)} />
              </div>
            </:col>
            <:col :let={postmortem} label={dgettext("postmortems", "Published")}>
              <.time_cell time={postmortem.inserted_at} />
            </:col>
          </.table>
          <div :if={@postmortems_meta.total_pages > 1} data-part="pagination">
            <.button
              variant="secondary"
              label={dgettext("postmortems", "Prev")}
              disabled={@postmortems_meta.current_page <= 1}
              patch={page_link(@uri, max(1, @postmortems_meta.current_page - 1))}
            >
              <:icon_left><.chevron_left /></:icon_left>
            </.button>
            <.button
              variant="secondary"
              label={dgettext("postmortems", "Next")}
              disabled={@postmortems_meta.current_page >= @postmortems_meta.total_pages}
              patch={
                page_link(
                  @uri,
                  min(@postmortems_meta.total_pages, @postmortems_meta.current_page + 1)
                )
              }
            >
              <:icon_right><.chevron_right /></:icon_right>
            </.button>
          </div>
        </.card_section>
      </.card>
    </section>
    """
  end

  defp author_name(%{created_by_user: %{name: name}}) when is_binary(name) and name != "", do: name

  defp author_name(%{created_by_user: %{email: email}}) when is_binary(email), do: email
  defp author_name(_postmortem), do: dgettext("postmortems", "Unknown")
end
