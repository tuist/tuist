defmodule AtlasWeb.PostmortemLive.Show do
  @moduledoc false

  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  import Noora.CheckboxControl

  alias Atlas.Engineering.Postmortems
  alias Atlas.Engineering.Postmortems.ActionItem
  alias AtlasWeb.Markdown

  @impl true
  def mount(%{"number" => number}, _session, socket) do
    case Postmortems.fetch_visible_postmortem_by_number(number, socket.assigns.current_user) do
      {:ok, postmortem} ->
        {:ok,
         socket
         |> assign(:page_title, Postmortems.title(postmortem))
         |> assign(:postmortem, postmortem)
         |> assign(:can_edit?, Postmortems.can_edit?(postmortem, socket.assigns.current_user))
         |> assign(:editing_action_item_id, nil)
         |> assign(:expanded_action_item_keys, MapSet.new())
         |> assign_action_item_form(Postmortems.change_action_item())}

      {:error, :not_found} ->
        {:ok, push_navigate(socket, to: ~p"/engineering/postmortems")}
    end
  end

  @impl true
  def handle_event("create_action_item", %{"action_item" => params}, socket) do
    case Postmortems.create_action_item(
           socket.assigns.postmortem,
           params,
           socket.assigns.current_user
         ) do
      {:ok, _action_item} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("postmortems", "Action item added."))
         |> reload_postmortem()
         |> assign(:editing_action_item_id, nil)
         |> assign_action_item_form(Postmortems.change_action_item())
         |> push_event("close-modal", %{id: "new-action-item-modal"})}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("postmortems", "You cannot manage action items.")
         )}

      {:error, changeset} ->
        {:noreply, assign_action_item_form(socket, Map.put(changeset, :action, :validate))}
    end
  end

  def handle_event("toggle_action_item", %{"id" => id}, socket) do
    with %ActionItem{} = action_item <- find_action_item(socket, id),
         {:ok, _action_item} <-
           Postmortems.toggle_action_item(
             socket.assigns.postmortem,
             action_item,
             socket.assigns.current_user
           ) do
      {:noreply, reload_postmortem(socket)}
    else
      _error ->
        {:noreply,
         put_flash(socket, :error, dgettext("postmortems", "Action item not found."))}
    end
  end

  def handle_event("update_action_item", %{"action_item" => params, "id" => id}, socket) do
    with %ActionItem{} = action_item <- find_action_item(socket, id),
         {:ok, _action_item} <-
           Postmortems.update_action_item(
             socket.assigns.postmortem,
             action_item,
             params,
             socket.assigns.current_user
           ) do
      {:noreply,
       socket
       |> put_flash(:info, dgettext("postmortems", "Action item updated."))
       |> reload_postmortem()
       |> assign(:editing_action_item_id, nil)
       |> assign_action_item_form(Postmortems.change_action_item())
       |> push_event("close-modal", %{id: "edit-action-item-modal-#{id}"})}
    else
      {:error, :unauthorized} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("postmortems", "You cannot manage action items.")
         )}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:editing_action_item_id, id)
         |> assign_action_item_form(Map.put(changeset, :action, :validate))}

      nil ->
        {:noreply,
         put_flash(socket, :error, dgettext("postmortems", "Action item not found."))}
    end
  end

  def handle_event("delete_action_item", %{"id" => id}, socket) do
    with %ActionItem{} = action_item <- find_action_item(socket, id),
         {:ok, _action_item} <-
           Postmortems.delete_action_item(
             socket.assigns.postmortem,
             action_item,
             socket.assigns.current_user
           ) do
      {:noreply,
       socket
       |> put_flash(:info, dgettext("postmortems", "Action item deleted."))
       |> reload_postmortem()}
    else
      _error ->
        {:noreply,
         put_flash(socket, :error, dgettext("postmortems", "Action item not found."))}
    end
  end

  def handle_event("toggle-expand", %{"row-key" => row_key}, socket) do
    expanded = socket.assigns.expanded_action_item_keys

    {:noreply,
     assign(
       socket,
       :expanded_action_item_keys,
       if(MapSet.member?(expanded, row_key),
         do: MapSet.delete(expanded, row_key),
         else: MapSet.put(expanded, row_key)
       )
     )}
  end

  def handle_event("close_new_action_item", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_action_item_id, nil)
     |> assign_action_item_form(Postmortems.change_action_item())
     |> push_event("close-modal", %{id: "new-action-item-modal"})}
  end

  def handle_event("close_action_item_modal", params, socket) do
    socket =
      socket
      |> assign(:editing_action_item_id, nil)
      |> assign_action_item_form(Postmortems.change_action_item())

    {:noreply,
     case params do
       %{"id" => id} -> push_event(socket, "close-modal", %{id: id})
       _params -> socket
     end}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="postmortems">
      <div data-part="header">
        <div data-part="title-group">
          <h1>{dgettext("postmortems", "Postmortem #%{number} · %{title}", number: @postmortem.number, title: Postmortems.title(@postmortem))}</h1>
        </div>
        <div data-part="header-actions">
          <.button
            :if={@can_edit?}
            label={dgettext("postmortems", "Edit")}
            href={~p"/engineering/postmortems/#{@postmortem.number}/edit"}
            size="medium"
            variant="primary"
          >
            <:icon_left><.pencil /></:icon_left>
          </.button>
        </div>
      </div>
      <.card icon="info_circle" title={dgettext("postmortems", "Summary")} data-part="summary-card">
        <.card_section>
          <div data-part="summary-grid">
            <div data-part="summary-item">
              <span data-part="label">{dgettext("postmortems", "Published")}</span>
              <span>{Calendar.strftime(@postmortem.inserted_at, "%b %d, %Y · %H:%M UTC")}</span>
            </div>
            <div data-part="summary-item">
              <span data-part="label">{dgettext("postmortems", "Author")}</span>
              <span>{author_label(@postmortem)}</span>
            </div>
            <div data-part="summary-item">
              <span data-part="label">{dgettext("postmortems", "Domains")}</span>
              <div :if={@postmortem.domains != []} data-part="domains">
                <.link :for={domain <- @postmortem.domains} navigate={~p"/engineering/domains/#{domain.id}"}>
                  <.badge label={domain.name} color="neutral" style="light-fill" size="large" />
                </.link>
              </div>
              <span :if={@postmortem.domains == []}>{dgettext("postmortems", "Unassigned")}</span>
            </div>
            <div data-part="summary-item">
              <span data-part="label">{dgettext("postmortems", "Action items")}</span>
              <span>{completed_action_item_count(@postmortem)}/{length(@postmortem.action_items)} {dgettext("postmortems", "complete")}</span>
            </div>
          </div>
        </.card_section>
      </.card>
      <.card icon="alert_triangle" title={dgettext("postmortems", "Postmortem")}>
        <.card_section>
          <Markdown.content id={"postmortem-#{@postmortem.number}-body"} body={@postmortem.body} data-part="body" />
        </.card_section>
      </.card>
      <.card icon="circle_check" title={dgettext("postmortems", "Action items")}>
        <:actions :if={@can_edit?}>
          <.modal
            id="new-action-item-modal"
            data-width="large"
            title={dgettext("postmortems", "Add action item")}
            description={dgettext("postmortems", "Record the follow-up work this incident requires.")}
            header_type="icon"
            header_size="large"
            on_dismiss="close_new_action_item"
          >
            <:trigger :let={attrs}>
              <.button label={dgettext("postmortems", "Add action item")} size="medium" variant="secondary" {attrs}>
                <:icon_left><.circle_plus /></:icon_left>
              </.button>
            </:trigger>
            <:header_icon><.circle_check /></:header_icon>
            <.line_divider />
            <.form for={@action_item_form} id="new-action-item" phx-submit="create_action_item" data-part="action-item-form">
              <.text_input id="new-action-item-title" field={@action_item_form[:title]} label={dgettext("postmortems", "Title")} placeholder={dgettext("postmortems", "Describe the follow-up work")} />
              <.action_item_priority_select id="new-action-item-priority" field={@action_item_form[:priority]} />
              <.text_area field={@action_item_form[:description]} label={dgettext("postmortems", "Description (optional)")} rows={4} max_length={5_000} />
              <.text_input field={@action_item_form[:resolution_url]} label={dgettext("postmortems", "Resolution link (optional)")} placeholder="https://github.com/tuist/tuist/pull/123" />
            </.form>
            <.line_divider />
            <:footer>
              <.modal_footer>
                <:action><.button label={dgettext("postmortems", "Cancel")} type="button" size="medium" variant="secondary" phx-click="close_new_action_item" /></:action>
                <:action><.button label={dgettext("postmortems", "Add action item")} type="submit" form="new-action-item" size="medium" variant="primary" /></:action>
              </.modal_footer>
            </:footer>
          </.modal>
        </:actions>
        <.card_section>
          <div data-part="action-items">
            <p :if={@postmortem.action_items == []} data-part="empty-action-items">{dgettext("postmortems", "No action items have been added.")}</p>
            <.table
              :if={@postmortem.action_items != []}
              id="postmortem-action-items-table"
              rows={@postmortem.action_items}
              row_key={&action_item_key/1}
              row_expandable={&has_details?/1}
              expanded_rows={MapSet.to_list(@expanded_action_item_keys)}
            >
              <:col :let={action_item} label={dgettext("postmortems", "Action item")}>
                <.action_item_cell action_item={action_item} can_edit?={@can_edit?} />
              </:col>
              <:col :let={action_item} label={dgettext("postmortems", "Priority")}>
                <.badge_cell label={priority_label(action_item.priority)} color={priority_color(action_item.priority)} style="light-fill" />
              </:col>
              <:col :let={action_item} label={dgettext("postmortems", "Status")}>
                <.badge_cell
                  label={if action_item.completed_at, do: dgettext("postmortems", "Completed"), else: dgettext("postmortems", "Open")}
                  color={if action_item.completed_at, do: "success", else: "neutral"}
                  style="light-fill"
                />
              </:col>
              <:col :if={@can_edit?} :let={action_item} label="">
                <% edit_form = action_item_form(action_item, @editing_action_item_id, @action_item_form) %>
                <.button_cell>
                  <:button>
                    <.modal
                      id={"edit-action-item-modal-#{action_item.id}"}
                      data-width="large"
                      title={dgettext("postmortems", "Edit action item")}
                      header_type="icon"
                      header_size="large"
                      on_dismiss="close_action_item_modal"
                    >
                      <:trigger :let={attrs}>
                        <.button label={dgettext("postmortems", "Edit action item")} title={dgettext("postmortems", "Edit action item")} type="button" size="large" variant="secondary" icon_only={true} {attrs}>
                          <.pencil />
                        </.button>
                      </:trigger>
                      <:header_icon><.pencil /></:header_icon>
                      <.line_divider />
                      <.form for={edit_form} id={"edit-action-item-#{action_item.id}"} phx-submit="update_action_item" phx-value-id={action_item.id} data-part="action-item-form">
                        <.text_input id={"edit-action-item-title-#{action_item.id}"} field={edit_form[:title]} label={dgettext("postmortems", "Title")} />
                        <.action_item_priority_select id={"edit-action-item-priority-#{action_item.id}"} field={edit_form[:priority]} />
                        <.text_area id={"edit-action-item-description-#{action_item.id}"} field={edit_form[:description]} label={dgettext("postmortems", "Description (optional)")} rows={4} max_length={5_000} />
                        <.text_input id={"edit-action-item-resolution-url-#{action_item.id}"} field={edit_form[:resolution_url]} label={dgettext("postmortems", "Resolution link (optional)")} placeholder="https://github.com/tuist/tuist/pull/123" />
                      </.form>
                      <.line_divider />
                      <:footer>
                        <.modal_footer>
                          <:action><.button label={dgettext("postmortems", "Cancel")} type="button" size="medium" variant="secondary" phx-click="close_action_item_modal" phx-value-id={"edit-action-item-modal-#{action_item.id}"} /></:action>
                          <:action><.button label={dgettext("postmortems", "Save changes")} type="submit" form={"edit-action-item-#{action_item.id}"} size="medium" variant="primary" /></:action>
                        </.modal_footer>
                      </:footer>
                    </.modal>
                  </:button>
                  <:button>
                    <.button
                      label={dgettext("postmortems", "Delete action item")}
                      title={dgettext("postmortems", "Delete action item")}
                      type="button"
                      size="large"
                      variant="secondary"
                      icon_only={true}
                      phx-click="delete_action_item"
                      phx-value-id={action_item.id}
                      data-confirm={dgettext("postmortems", "Delete this action item?")}
                    >
                      <.trash />
                    </.button>
                  </:button>
                </.button_cell>
              </:col>
              <:expanded_content :let={action_item}>
                <div data-part="action-item-details">
                  <div :if={has_description?(action_item)} data-part="detail">
                    <span data-part="label">{dgettext("postmortems", "Description")}</span>
                    <Markdown.content id={"#{action_item_key(action_item)}-description"} body={action_item.description} data-part="description" />
                  </div>
                  <div :if={has_resolution_url?(action_item)} data-part="detail">
                    <span data-part="label">{dgettext("postmortems", "Resolved by")}</span>
                    <.link href={action_item.resolution_url} target="_blank" rel="noopener noreferrer">{action_item.resolution_url}</.link>
                  </div>
                </div>
              </:expanded_content>
            </.table>
          </div>
        </.card_section>
      </.card>
    </section>
    """
  end

  defp assign_action_item_form(socket, changeset),
    do: assign(socket, :action_item_form, to_form(changeset, as: :action_item))

  defp action_item_form(%ActionItem{id: id}, id, form), do: form

  defp action_item_form(action_item, _editing_action_item_id, _form),
    do: to_form(Postmortems.change_action_item(action_item), as: :action_item)

  attr :id, :string, required: true
  attr :field, Phoenix.HTML.FormField, required: true

  defp action_item_priority_select(assigns) do
    ~H"""
    <div data-part="select-field">
      <span>{dgettext("postmortems", "Priority")}</span>
      <.select
        id={@id}
        name={@field.name}
        value={Phoenix.HTML.Form.normalize_value("select", @field.value)}
        label={dgettext("postmortems", "Choose priority")}
      >
        <:item :for={priority <- ActionItem.priorities()} value={to_string(priority)} label={priority_label(priority)} />
      </.select>
    </div>
    """
  end

  attr :action_item, ActionItem, required: true
  attr :can_edit?, :boolean, required: true

  defp action_item_cell(assigns) do
    ~H"""
    <.text_cell label={@action_item.title}>
      <:image :if={@can_edit? or @action_item.completed_at}>
        <.action_item_control action_item={@action_item} can_edit?={@can_edit?} />
      </:image>
    </.text_cell>
    """
  end

  attr :action_item, ActionItem, required: true
  attr :can_edit?, :boolean, required: true

  defp action_item_control(assigns) do
    ~H"""
    <button :if={@can_edit?} type="button" data-part="action-item-toggle" phx-click="toggle_action_item" phx-value-id={@action_item.id} title={dgettext("postmortems", "Toggle action item status")} aria-label={dgettext("postmortems", "Toggle action item status")}>
      <.checkbox_control checked={not is_nil(@action_item.completed_at)} />
    </button>
    <.check :if={!@can_edit? and @action_item.completed_at} />
    """
  end

  defp has_description?(%{description: description}) when is_binary(description),
    do: String.trim(description) != ""

  defp has_description?(_action_item), do: false

  defp has_resolution_url?(%{resolution_url: resolution_url}) when is_binary(resolution_url),
    do: String.trim(resolution_url) != ""

  defp has_resolution_url?(_action_item), do: false

  defp has_details?(action_item),
    do: has_description?(action_item) or has_resolution_url?(action_item)

  defp action_item_key(%ActionItem{id: id}), do: "action-item-#{id}"

  defp priority_label(:immediate), do: dgettext("postmortems", "Immediate")
  defp priority_label(:high), do: dgettext("postmortems", "High")
  defp priority_label(:medium), do: dgettext("postmortems", "Medium")
  defp priority_label(:low), do: dgettext("postmortems", "Low")

  defp priority_color(:immediate), do: "destructive"
  defp priority_color(:high), do: "warning"
  defp priority_color(:medium), do: "information"
  defp priority_color(:low), do: "neutral"

  defp reload_postmortem(socket),
    do:
      assign(
        socket,
        :postmortem,
        Postmortems.get_postmortem_by_number!(socket.assigns.postmortem.number)
      )

  defp find_action_item(socket, id),
    do: Enum.find(socket.assigns.postmortem.action_items, &(&1.id == id))

  defp completed_action_item_count(postmortem),
    do: Enum.count(postmortem.action_items, & &1.completed_at)

  defp author_label(%{created_by_user: %{name: name}}) when is_binary(name) and name != "",
    do: name

  defp author_label(%{created_by_user: %{email: email}}) when is_binary(email), do: email
  defp author_label(_postmortem), do: dgettext("postmortems", "Atlas")
end
