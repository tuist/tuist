defmodule AtlasWeb.SpecLive.Index do
  @moduledoc false

  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Engineering.Specs
  alias Atlas.Engineering.Specs.Spec
  alias AtlasWeb.Markdown
  alias Noora.Filter.Filter
  alias Noora.Filter.Operations

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, dgettext("specs", "Specs"))
     |> assign(:available_filters, available_filters())
     |> assign(:active_filters, [])
     |> assign(:uri, URI.parse("/engineering/specs"))
     |> assign(:specs, [])
     |> assign(:can_create?, Specs.can_create?(socket.assigns.current_user))}
  end

  @impl true
  def handle_params(params, uri, socket) do
    active_filters =
      Operations.decode_filters_from_query(params, socket.assigns.available_filters)

    specs =
      Specs.list_specs(
        status: status_filter(active_filters),
        user: socket.assigns.current_user
      )

    {:noreply,
     socket
     |> assign(:uri, URI.parse(uri))
     |> assign(:active_filters, active_filters)
     |> assign(:specs, specs)}
  end

  @impl true
  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    params = Operations.add_filter_to_query(filter_id, socket)
    {:noreply, push_patch(socket, to: ~p"/engineering/specs?#{params}")}
  end

  def handle_event("update_filter", params, socket) do
    params = Operations.update_filters_in_query(params, socket)
    {:noreply, push_patch(socket, to: ~p"/engineering/specs?#{params}")}
  end

  defp available_filters do
    [
      %Filter{
        id: "status",
        field: :status,
        display_name: dgettext("specs", "Status"),
        type: :option,
        options: Spec.statuses(),
        options_display_names: Map.new(Spec.statuses(), &{&1, status_label(&1)}),
        operator: :==,
        value: :draft
      }
    ]
  end

  defp status_filter(active_filters) do
    case Enum.find(active_filters, &(&1.id == "status")) do
      %{operator: :==, value: status} when is_atom(status) -> status
      %{operator: :!=, value: status} when is_atom(status) -> {:not, status}
      _filter -> nil
    end
  end

  defp status_label(:draft), do: dgettext("specs", "Draft")
  defp status_label(:proposed), do: dgettext("specs", "Proposed")
  defp status_label(:approved), do: dgettext("specs", "Approved")
  defp status_label(:paused), do: dgettext("specs", "Paused")
  defp status_label(:rejected), do: dgettext("specs", "Rejected")
  defp status_label(:in_progress), do: dgettext("specs", "In progress")
  defp status_label(:shipped), do: dgettext("specs", "Shipped")
  defp status_label(:archived), do: dgettext("specs", "Archived")

  defp status_label(status), do: status |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  defp status_color(:draft), do: "neutral"
  defp status_color(:proposed), do: "primary"
  defp status_color(:approved), do: "success"
  defp status_color(:in_progress), do: "attention"
  defp status_color(:shipped), do: "success"
  defp status_color(:paused), do: "warning"
  defp status_color(:rejected), do: "destructive"
  defp status_color(:archived), do: "neutral"
  defp status_color(_status), do: "neutral"

  defp author_name(%{created_by_user: %{name: name}}) when is_binary(name) and name != "", do: name
  defp author_name(%{created_by_user: %{email: email}}) when is_binary(email), do: email
  defp author_name(_spec), do: dgettext("specs", "Unknown")

  @impl true
  def render(assigns) do
    ~H"""
    <section id="specs">
      <div data-part="header">
        <div data-part="title-group">
          <h1>{dgettext("specs", "Specs")}</h1>
          <p>{dgettext("specs", "Editable engineering proposals shaped by the team.")}</p>
        </div>
        <div data-part="header-actions">
          <.button
            :if={@can_create?}
            label={dgettext("specs", "New spec")}
            href={~p"/engineering/specs/new"}
            size="medium"
            variant="primary"
          >
            <:icon_left><.circle_plus /></:icon_left>
          </.button>
        </div>
      </div>
      <.card icon="file_text" title={dgettext("specs", "Specs")}>
        <.card_section>
          <div data-part="table-toolbar">
            <.filter_dropdown
              id="specs-filter"
              label={dgettext("specs", "Filter")}
              available_filters={@available_filters}
              active_filters={@active_filters}
              on_select="add_filter"
            />
          </div>
          <div :if={@active_filters != []} data-part="active-filters">
            <.active_filter :for={filter <- @active_filters} filter={filter} />
          </div>
          <div :if={@specs == []} data-part="empty-state">
            <div data-part="empty-icon"><.icon name="file_text" /></div>
            <h2>{dgettext("specs", "No specs yet")}</h2>
            <p>{dgettext("specs", "Draft the first proposal to see it here.")}</p>
          </div>
          <.table
            :if={@specs != []}
            id="specs-table"
            rows={@specs}
            row_navigate={fn spec -> ~p"/engineering/specs/#{spec.number}" end}
          >
            <:col :let={spec} label={dgettext("specs", "Spec")}>
              <.text_and_description_cell
                label={
                  dgettext("specs", "#%{number} %{title}",
                    number: spec.number,
                    title: Specs.title(spec)
                  )
                }
                description={Markdown.preview(spec.summary || spec.body)}
                icon="file_text"
              />
            </:col>
            <:col :let={spec} label={dgettext("specs", "Author")}>
              <div data-part="author-cell">
                <.text_and_description_cell label={author_name(spec)} />
              </div>
            </:col>
            <:col :let={spec} label={dgettext("specs", "Domains")}>
              <div data-part="cell" data-type="badge">
                <div data-part="spec-table-domains-cell">
                  <span
                    :if={spec.domains == []}
                    data-part="empty-domains"
                  >
                    {dgettext("specs", "No domains")}
                  </span>
                  <.badge
                    :for={domain <- spec.domains}
                    label={domain.name}
                    color="neutral"
                    style="light-fill"
                    size="large"
                  />
                </div>
              </div>
            </:col>
            <:col :let={spec} label={dgettext("specs", "Status")}>
              <.badge
                label={status_label(spec.status)}
                color={status_color(spec.status)}
                style="light-fill"
                size="large"
              />
            </:col>
            <:col :let={spec} label={dgettext("specs", "Updated")}>
              <.time_cell time={spec.updated_at} />
            </:col>
          </.table>
        </.card_section>
      </.card>
    </section>
    """
  end
end
