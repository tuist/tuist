defmodule AtlasWeb.SpecLive.Show do
  @moduledoc false

  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Engineering.Specs
  alias Atlas.Engineering.Specs.Spec
  alias AtlasWeb.Markdown

  @impl true
  def mount(%{"number" => number}, _session, socket) do
    case Specs.fetch_visible_spec_by_number(number, socket.assigns.current_user) do
      {:ok, spec} ->
        Specs.mark_viewed(spec, socket.assigns.current_user)

        {:ok,
         socket
         |> assign(:page_title, Specs.title(spec))
         |> assign(:spec, spec)
         |> assign(:can_edit?, Specs.can_edit?(spec, socket.assigns.current_user))
         |> assign(:can_comment?, Specs.can_comment?(spec, socket.assigns.current_user))
         |> assign_comment_form(Specs.change_comment())}

      {:error, :not_found} ->
        {:ok, push_navigate(socket, to: ~p"/engineering/specs")}
    end
  end

  @impl true
  def handle_event("add_comment", %{"comment" => params}, socket) do
    case Specs.add_comment(socket.assigns.spec, params, socket.assigns.current_user) do
      {:ok, _comment} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("specs", "Comment added."))
         |> reload_spec()
         |> assign_comment_form(Specs.change_comment())}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, dgettext("specs", "You cannot comment on this spec."))}

      {:error, changeset} ->
        {:noreply, assign_comment_form(socket, Map.put(changeset, :action, :validate))}
    end
  end

  def handle_event("delete_comment", %{"id" => id}, socket) do
    comment = Specs.get_comment!(id)

    case Specs.delete_comment(comment, socket.assigns.current_user) do
      {:ok, _} ->
        {:noreply, reload_spec(socket)}

      _ ->
        {:noreply, put_flash(socket, :error, dgettext("specs", "Comment not found."))}
    end
  end

  def handle_event("change_status", %{"value" => value}, socket) do
    status = String.to_existing_atom(value)

    if status in Spec.statuses() do
      case Specs.update_spec(socket.assigns.spec, %{"status" => value}, socket.assigns.current_user) do
        {:ok, _spec} ->
          {:noreply,
           socket
           |> put_flash(:info, dgettext("specs", "Status updated."))
           |> reload_spec()}

        {:error, :unauthorized} ->
          {:noreply, put_flash(socket, :error, dgettext("specs", "You cannot edit this spec."))}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, dgettext("specs", "Could not update status."))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete_spec", _params, socket) do
    case Specs.delete_spec(socket.assigns.spec, socket.assigns.current_user) do
      {:ok, _spec} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("specs", "Spec deleted."))
         |> push_navigate(to: ~p"/engineering/specs")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, dgettext("specs", "You cannot delete this spec."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("specs", "Could not delete spec. Refresh and retry."))}
    end
  end

  defp reload_spec(socket) do
    assign(socket, :spec, Specs.get_spec!(socket.assigns.spec.id))
  end

  defp assign_comment_form(socket, changeset), do: assign(socket, :comment_form, to_form(changeset, as: :comment))

  @impl true
  def render(assigns) do
    ~H"""
    <section id="specs">
      <div data-part="header">
        <div data-part="title-group">
          <h1>
            {dgettext("specs", "#%{number} %{title}",
              number: @spec.number,
              title: Specs.title(@spec)
            )}
          </h1>
          <p :if={@spec.summary}>{@spec.summary}</p>
        </div>
        <div data-part="header-actions">
          <div :if={@can_edit?} data-part="status-menu">
            <.dropdown
              id="spec-status-dropdown"
              label={status_label(@spec.status)}
              on_select="change_status"
            >
              <.dropdown_item
                :for={status <- Spec.statuses()}
                value={to_string(status)}
                label={status_label(status)}
              />
            </.dropdown>
          </div>
          <.button
            :if={@can_edit?}
            label={dgettext("specs", "Edit")}
            href={~p"/engineering/specs/#{@spec.number}/edit"}
            size="medium"
            variant="secondary"
          />
          <.button
            :if={@can_edit?}
            label={dgettext("specs", "Delete")}
            phx-click="delete_spec"
            data-confirm={dgettext("specs", "Delete this spec?")}
            size="medium"
            variant="destructive"
          />
        </div>
      </div>
      <.card icon="file_text" title={dgettext("specs", "Body")}>
        <.card_section>
          <Markdown.content
            id={"spec-#{@spec.number}-body"}
            body={@spec.body}
            data-part="body"
          />
        </.card_section>
      </.card>
      <.card icon="message_circle" title={dgettext("specs", "Comments")}>
        <.card_section>
          <div :if={@spec.comments == []} data-part="empty-state">
            <p>{dgettext("specs", "No comments yet.")}</p>
          </div>
          <ul :if={@spec.comments != []} data-part="comment-list">
            <li
              :for={comment <- @spec.comments}
              id={"comment-#{comment.id}"}
              data-part="comment"
            >
              <div data-part="comment-card">
                <div data-part="comment-header">
                  <div data-part="comment-author">
                    <strong>{comment_author(comment)}</strong>
                    <.time_cell time={comment.inserted_at} />
                  </div>
                  <div
                    :if={Specs.can_edit_comment?(comment, @current_user)}
                    data-part="comment-actions"
                  >
                    <.button
                      label={dgettext("specs", "Delete")}
                      phx-click="delete_comment"
                      phx-value-id={comment.id}
                      data-confirm={dgettext("specs", "Delete this comment?")}
                      size="small"
                      variant="secondary"
                    />
                  </div>
                </div>
                <div data-part="comment-body">
                  <Markdown.content
                    id={"spec-#{@spec.number}-comment-#{comment.id}"}
                    body={comment.body}
                  />
                </div>
              </div>
            </li>
          </ul>
          <.form
            :if={@can_comment?}
            for={@comment_form}
            id="spec-comment-form"
            phx-submit="add_comment"
            data-part="comment-form"
          >
            <.text_area
              field={@comment_form[:body]}
              label={dgettext("specs", "Add a comment")}
              rows={4}
              max_length={20_000}
            />
            <div data-part="form-actions">
              <.button
                label={dgettext("specs", "Post comment")}
                size="medium"
                variant="primary"
                type="submit"
              />
            </div>
          </.form>
        </.card_section>
      </.card>
    </section>
    """
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

  defp comment_author(%{user: %{name: name}}) when is_binary(name) and name != "", do: name
  defp comment_author(%{user: %{email: email}}) when is_binary(email), do: email
  defp comment_author(%{author_name: name}) when is_binary(name) and name != "", do: name
  defp comment_author(_comment), do: dgettext("specs", "Anonymous")
end
