defmodule AtlasWeb.MoodboardShowLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []
  import AtlasWeb.MoodboardComponents
  import AtlasWeb.MoodboardMedia, only: [media: 1]
  import AtlasWeb.PaginationComponents
  import Noora.Time, only: [time: 1]

  alias Atlas.Moodboard
  alias Atlas.Moodboard.Comment

  @page_size 30

  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, 10_000)

    {:ok,
     socket
     |> assign(:comment_offset, 0)
     |> assign(:resource_modal_open, false)
     |> assign(:deleted, false)
     |> assign(:comment_form, to_form(Comment.changeset(%Comment{}, %{}), as: :comment))}
  end

  def handle_params(%{"id" => id} = params, uri, socket) do
    socket = socket |> assign(:uri, URI.parse(uri)) |> assign(:comment_offset, parse_offset(params["comments_offset"]))
    load_resource(socket, id)
  end

  def handle_info(:refresh, %{assigns: %{deleted: true}} = socket), do: {:noreply, socket}

  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, 10_000)
    load_resource(socket, socket.assigns.resource.id)
  end

  def handle_event("comment", %{"comment" => attrs}, socket) do
    case Moodboard.add_comment(socket.assigns.resource.id, attrs, socket.assigns.current_user, interface: "dashboard") do
      {:ok, _comment} ->
        last = Moodboard.last_comment_offset(socket.assigns.current_user, socket.assigns.resource.id, @page_size)

        {:noreply,
         socket
         |> assign(:comment_form, to_form(Comment.changeset(%Comment{}, %{}), as: :comment))
         |> put_flash(:info, gettext("Comment added."))
         |> push_patch(to: comment_path(socket.assigns.resource.id, last), replace: true)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :comment_form, to_form(changeset, as: :comment))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("This resource is no longer available."))}
    end
  end

  def handle_event("delete_comment", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.comments, &(&1.id == id)) do
      case Moodboard.delete_comment(id, socket.assigns.current_user, interface: "dashboard") do
        {:ok, _} -> {:noreply, load_comments(socket)}
        _ -> {:noreply, put_flash(socket, :error, gettext("Only the author can remove a comment."))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit_resource", _params, socket) do
    {:noreply, assign(socket, :resource_form, resource_form(socket.assigns.resource))}
  end

  def handle_event("save", %{"resource" => attrs}, socket) do
    attrs = Map.update(attrs, "tags", [], &String.split(&1, ","))

    case Moodboard.update_resource(socket.assigns.resource.id, attrs, socket.assigns.current_user,
           interface: "dashboard"
         ) do
      {:ok, resource} ->
        {:noreply,
         socket
         |> assign(:resource, resource)
         |> assign(:page_title, resource.title)
         |> put_flash(:info, gettext("Resource saved to Moodboard."))
         |> push_event("close-modal", %{id: "moodboard-resource-modal"})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :resource_form, resource_form(changeset, attrs["tags"]))}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("This resource is not yours to edit."))}
    end
  end

  def handle_event("delete", _params, socket) do
    case Moodboard.delete_resource(socket.assigns.resource.id, socket.assigns.current_user, interface: "dashboard") do
      {:ok, _} ->
        socket = socket |> assign(:deleted, true) |> put_flash(:info, gettext("Resource removed."))

        if socket.assigns.resource_modal_open do
          {:noreply, push_event(socket, "close-modal", %{id: "moodboard-resource-modal"})}
        else
          {:noreply, push_navigate(socket, to: ~p"/library/moodboard")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Only the contributor can remove this resource."))}
    end
  end

  def handle_event("close_resource_modal", _params, socket),
    do: {:noreply, push_event(socket, "close-modal", %{id: "moodboard-resource-modal"})}

  def handle_event("resource_modal_changed", %{"open" => open}, socket) do
    socket = assign(socket, :resource_modal_open, open)

    if socket.assigns.deleted and not open,
      do: {:noreply, push_navigate(socket, to: ~p"/library/moodboard")},
      else: {:noreply, socket}
  end

  def handle_event("refresh_preview", _params, socket) do
    case Moodboard.refresh_preview(socket.assigns.resource.id, socket.assigns.current_user, interface: "dashboard") do
      {:ok, resource} -> {:noreply, assign(socket, :resource, resource)}
      _ -> {:noreply, put_flash(socket, :error, gettext("Only the contributor can refresh this preview."))}
    end
  end

  defp load_resource(socket, id) do
    case Moodboard.get_resource(socket.assigns.current_user, id) do
      nil ->
        {:noreply,
         socket |> put_flash(:error, gettext("Resource not found.")) |> push_navigate(to: ~p"/library/moodboard")}

      resource ->
        socket =
          if Map.has_key?(socket.assigns, :resource_form),
            do: socket,
            else: assign(socket, :resource_form, resource_form(resource))

        {:noreply, socket |> assign(:resource, resource) |> assign(:page_title, resource.title) |> load_comments()}
    end
  end

  defp load_comments(socket) do
    {comments, more} =
      Moodboard.list_comments(socket.assigns.current_user, socket.assigns.resource.id,
        limit: @page_size,
        offset: socket.assigns.comment_offset
      )

    socket
    |> assign(:comments, comments)
    |> assign(:more_comments, more)
    |> assign(:previous_cursor, Integer.to_string(max(socket.assigns.comment_offset - @page_size, 0)))
    |> assign(:next_cursor, Integer.to_string(socket.assigns.comment_offset + @page_size))
  end

  defp parse_offset(value) when is_binary(value) do
    case Integer.parse(value) do
      {offset, ""} when offset >= 0 -> min(offset, 1_000_000)
      _ -> 0
    end
  end

  defp parse_offset(_value), do: 0
  defp comment_path(id, 0), do: ~p"/library/moodboard/#{id}"
  defp comment_path(id, offset), do: ~p"/library/moodboard/#{id}?comments_offset=#{offset}"
  defp author_name(comment), do: (comment.author && comment.author.name) || gettext("a teammate")

  def render(assigns) do
    ~H"""
    <div id="moodboard-resource-detail">
      <div data-part="header">
        <div data-part="text">
          <.breadcrumbs data-part="breadcrumbs">
            <.breadcrumb
              id="moodboard-breadcrumb-list"
              label={gettext("Moodboard")}
              phx-click={JS.navigate(~p"/library/moodboard")}
            />
            <.breadcrumb id="moodboard-breadcrumb-current" label={@resource.title} />
          </.breadcrumbs>
          <h1 data-part="title">{@resource.title}</h1>
          <p data-part="description">
            {gettext("Shared by %{name}",
              name: (@resource.created_by && @resource.created_by.name) || gettext("a teammate")
            )}
          </p>
          <div data-part="summary">
            <.badge label={kind_label(@resource.kind)} color="neutral" style="light-fill" />
            <.preview_status :if={@resource.url} status={@resource.preview_status} />
          </div>
        </div>
        <div data-part="header-actions">
          <.button
            :if={@resource.url}
            id="moodboard-open-source"
            label={gettext("Open original")}
            href={@resource.url}
            target="_blank"
            rel="noopener noreferrer"
            variant="secondary"
          >
            <:icon_right><.external_link /></:icon_right>
          </.button>
          <.resource_modal
            :if={@resource.created_by_id == @current_user.id}
            form={@resource_form}
            editing
          >
            <:trigger :let={attrs}>
              <.button
                id="moodboard-edit-resource"
                label={gettext("Edit")}
                phx-click="edit_resource"
                variant="secondary"
                {attrs}
              />
            </:trigger>
          </.resource_modal>
          <.button
            :if={@resource.created_by_id == @current_user.id}
            id="moodboard-remove-resource"
            label={gettext("Remove resource")}
            phx-click="delete"
            variant="destructive"
            data-confirm={gettext("Remove this resource and its discussion from Moodboard?")}
          />
        </div>
      </div>
      <div data-part="detail-layout">
        <div data-part="detail-main">
          <.card title={gettext("Resource")} icon="book">
            <.card_section data-part="detail-section">
              <.media
                :if={
                  @resource.image_url || @resource.preview_image_url || @resource.preview_video_url
                }
                resource={@resource}
                id={"detail-media-#{@resource.id}"}
                detail
              />
              <div :if={@resource.description} id="moodboard-contributor-note" data-part="prose">
                <h2>{gettext("Contributor's note")}</h2>
                <p>{@resource.description}</p>
              </div>
              <div :if={@resource.content} id="moodboard-original-text" data-part="prose">
                <h2>{gettext("Text or excerpt")}</h2>
                <p>{@resource.content}</p>
              </div>
              <div :if={@resource.source_description} id="moodboard-source-summary" data-part="prose">
                <h2>{gettext("From the source")}</h2>
                <p>{@resource.source_description}</p>
              </div>
              <details :if={@resource.source_text} id="moodboard-source-text" data-part="prose">
                <summary>{gettext("Read extracted text")}</summary>
                <p>{@resource.source_text}</p>
              </details>
            </.card_section>
          </.card>
          <.card title={gettext("Discussion")} icon="message_circle">
            <.card_section data-part="detail-section">
              <div :if={@comments == []} id="moodboard-no-comments" data-part="comments-empty">
                <strong>
                  {if @comment_offset == 0,
                    do: gettext("No comments yet"),
                    else: gettext("No comments on this page")}
                </strong>
                <span>{gettext("What caught your eye? Start the conversation.")}</span>
              </div>
              <div id="moodboard-comments" data-part="comments">
                <article :for={comment <- @comments} id={"comment-#{comment.id}"} data-part="comment">
                  <.avatar
                    id={"comment-avatar-#{comment.id}"}
                    name={author_name(comment)}
                    image_alt=""
                    size="small"
                  />
                  <div data-part="comment-content">
                    <div data-part="comment-meta">
                      <strong>{author_name(comment)}</strong>
                      <.time time={comment.inserted_at} show_time />
                    </div>
                    <p>{comment.body}</p>
                  </div>
                  <div :if={comment.author_id == @current_user.id} data-part="comment-actions">
                    <.button
                      id={"delete-comment-#{comment.id}"}
                      label={gettext("Remove")}
                      phx-click="delete_comment"
                      phx-value-id={comment.id}
                      data-confirm={gettext("Remove this comment?")}
                      variant="secondary"
                      size="small"
                    />
                  </div>
                </article>
              </div>
              <nav
                :if={@comment_offset > 0 or @more_comments}
                id="moodboard-comment-pagination"
                aria-label={gettext("Comment pages")}
              >
                <.pagination
                  uri={@uri}
                  has_previous_page={@comment_offset > 0}
                  has_next_page={@more_comments}
                  start_cursor={@previous_cursor}
                  end_cursor={@next_cursor}
                  before_param="comments_offset"
                  after_param="comments_offset"
                />
              </nav>
              <.form
                id="moodboard-comment-form"
                for={@comment_form}
                phx-submit="comment"
                data-part="comment-form"
              >
                <.text_area
                  id="moodboard-comment-body"
                  field={@comment_form[:body]}
                  label={gettext("Your comment")}
                  rows={4}
                  max_length={4000}
                  required
                />
                <div data-part="comment-composer-actions">
                  <.button
                    id="moodboard-comment-submit"
                    label={gettext("Add comment")}
                    size="small"
                    type="submit"
                  />
                </div>
              </.form>
            </.card_section>
          </.card>
        </div>
        <aside data-part="detail-side">
          <.card title={gettext("Properties")} icon="settings">
            <:actions>
              <.button
                :if={@resource.url && @resource.created_by_id == @current_user.id}
                id="moodboard-refresh-preview"
                label={gettext("Refresh preview")}
                phx-click="refresh_preview"
                variant="secondary"
                size="small"
              />
            </:actions>
            <.card_section data-part="detail-section">
              <div :if={@resource.url} data-part="property">
                <span data-part="property-label">{gettext("Source")}</span><a
                  href={@resource.url}
                  target="_blank"
                  rel="noopener noreferrer"
                >{URI.parse(@resource.url).host}</a>
              </div>
              <div data-part="property">
                <span data-part="property-label">{gettext("Added by")}</span>
                <div data-part="property-person">
                  <.avatar
                    id="moodboard-contributor-avatar"
                    size="small"
                    name={
                      (@resource.created_by && @resource.created_by.name) || gettext("a teammate")
                    }
                    image_alt=""
                  />
                  <span>
                    {(@resource.created_by && @resource.created_by.name) || gettext("a teammate")}
                  </span>
                </div>
              </div>
              <div data-part="property">
                <span data-part="property-label">{gettext("Added")}</span>
                <.time time={@resource.inserted_at} show_time />
              </div>
              <div :if={@resource.tags != []} data-part="property">
                <span data-part="property-label">{gettext("Tags")}</span>
                <div data-part="tags">
                  <.link
                    :for={tag <- @resource.tags}
                    navigate={~p"/library/moodboard?tag=#{tag}"}
                    aria-label={gettext("Filter by %{tag}", tag: tag)}
                  >
                    <.tag label={tag} />
                  </.link>
                </div>
              </div>
              <div :if={@resource.preview_fetched_at} data-part="property">
                <span data-part="property-label">{gettext("Preview updated")}</span>
                <.time time={@resource.preview_fetched_at} show_time />
              </div>
              <p :if={@resource.preview_status == "unavailable"} data-part="preview-status">
                {gettext(
                  "A preview wasn't available. Private, deleted, or blocked links can still be saved."
                )}
              </p>
            </.card_section>
          </.card>
        </aside>
      </div>
    </div>
    """
  end
end
