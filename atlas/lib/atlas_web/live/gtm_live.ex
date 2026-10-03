defmodule AtlasWeb.GTMLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.GTM
  alias Atlas.GTM.BlogPostIdea
  alias Atlas.GTM.SocialChannelIdea
  alias AtlasWeb.Utilities.Query
  alias Phoenix.HTML.Form

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, uri, socket) do
    query_params =
      uri
      |> Query.query_params()

    normalized_query_params = normalize_query_params(query_params, socket.assigns.live_action)

    uri =
      normalized_query_params
      |> URI.encode_query()
      |> then(&URI.new!("?" <> &1))

    params =
      params
      |> Map.drop(Map.keys(query_params))
      |> Map.merge(normalized_query_params)

    socket =
      socket
      |> assign(:uri, uri)
      |> assign_page(socket.assigns.live_action, params)

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div id={@page_id} data-part="gtm-page">
      <%= case @live_action do %>
        <% :content -> %>
          <.content_view ideas={@ideas} idea_form={@idea_form} />
        <% :idea -> %>
          <.idea_view idea={@idea} idea_form={@idea_form} comment_form={@comment_form} />
        <% :social -> %>
          <.social_view social_ideas={@social_ideas} social_idea_form={@social_idea_form} />
        <% :social_idea -> %>
          <.social_idea_view
            social_idea={@social_idea}
            social_idea_form={@social_idea_form}
            post_revision_form={@post_revision_form}
          />
      <% end %>
    </div>
    """
  end

  defp assign_page(socket, :content, _params) do
    socket
    |> assign(:page_id, "gtm-content")
    |> assign(:page_title, gettext("Content"))
    |> assign(:ideas, GTM.list_blog_post_ideas())
    |> assign_new_idea_form()
  end

  defp assign_page(socket, :idea, %{"id" => id}) do
    case GTM.get_blog_post_idea(id) do
      nil ->
        socket
        |> put_flash(:error, gettext("Blog post idea not found."))
        |> push_navigate(to: ~p"/commercial/gtm/content")

      idea ->
        socket
        |> assign(:page_id, "gtm-idea")
        |> assign(:page_title, idea.title)
        |> assign(:idea, idea)
        |> assign_idea_form(idea)
        |> assign_comment_form(idea)
    end
  end

  defp assign_page(socket, :social, _params) do
    socket
    |> assign(:page_id, "gtm-social")
    |> assign(:page_title, gettext("Social"))
    |> assign(:social_ideas, GTM.list_social_channel_ideas())
    |> assign_new_social_idea_form()
  end

  defp assign_page(socket, :social_idea, %{"id" => id}) do
    case GTM.get_social_channel_idea(id) do
      nil ->
        socket
        |> put_flash(:error, gettext("Social idea not found."))
        |> push_navigate(to: ~p"/commercial/gtm/social")

      social_idea ->
        socket
        |> assign(:page_id, "gtm-social-idea")
        |> assign(:page_title, social_idea.title)
        |> assign(:social_idea, social_idea)
        |> assign_social_idea_form(social_idea)
        |> assign_new_social_post_revision_form(social_idea)
    end
  end

  def handle_event("validate_new_idea", %{"blog_post_idea" => params}, socket) do
    form =
      %BlogPostIdea{}
      |> GTM.change_blog_post_idea(params)
      |> Map.put(:action, :validate)
      |> to_form(as: "blog_post_idea")

    {:noreply, assign(socket, :idea_form, form)}
  end

  def handle_event("create_idea", %{"blog_post_idea" => params}, socket) do
    case GTM.create_blog_post_idea(params, socket.assigns.current_user, announce: true) do
      {:ok, _idea} ->
        {:noreply,
         socket
         |> assign(:ideas, GTM.list_blog_post_ideas())
         |> assign_new_idea_form()
         |> push_event("close-modal", %{id: "new-idea-modal"})}

      {:error, changeset} ->
        {:noreply, assign(socket, :idea_form, to_form(changeset, as: "blog_post_idea"))}
    end
  end

  def handle_event("close-new-idea-modal", _params, socket) do
    {:noreply, push_event(socket, "close-modal", %{id: "new-idea-modal"})}
  end

  def handle_event("validate_idea", %{"blog_post_idea" => params}, socket) do
    form =
      socket.assigns.idea
      |> GTM.change_blog_post_idea(params)
      |> Map.put(:action, :validate)
      |> to_form(as: "blog_post_idea")

    {:noreply, assign(socket, :idea_form, form)}
  end

  def handle_event("save_idea", %{"blog_post_idea" => params}, socket) do
    case GTM.update_blog_post_idea(socket.assigns.idea, params) do
      {:ok, _idea} ->
        idea = GTM.get_blog_post_idea(socket.assigns.idea.id)

        {:noreply,
         socket
         |> assign(:idea, idea)
         |> assign(:page_title, idea.title)
         |> assign_idea_form(idea)}

      {:error, changeset} ->
        {:noreply, assign(socket, :idea_form, to_form(changeset, as: "blog_post_idea"))}
    end
  end

  def handle_event("add_idea_comment", %{"comment" => params}, socket) do
    case GTM.create_blog_post_idea_comment(
           socket.assigns.idea,
           params,
           socket.assigns.current_user
         ) do
      {:ok, _comment} ->
        idea = GTM.get_blog_post_idea(socket.assigns.idea.id)

        {:noreply,
         socket
         |> assign(:idea, idea)
         |> assign_comment_form(idea)}

      {:error, changeset} ->
        {:noreply, assign(socket, :comment_form, to_form(changeset, as: "comment"))}
    end
  end

  def handle_event("validate_new_social_idea", %{"social_channel_idea" => params}, socket) do
    form =
      %SocialChannelIdea{}
      |> GTM.change_social_channel_idea(params)
      |> Map.put(:action, :validate)
      |> to_form(as: "social_channel_idea")

    {:noreply, assign(socket, :social_idea_form, form)}
  end

  def handle_event("create_social_idea", %{"social_channel_idea" => params}, socket) do
    case GTM.create_social_channel_idea(params, socket.assigns.current_user) do
      {:ok, _idea} ->
        {:noreply,
         socket
         |> assign(:social_ideas, GTM.list_social_channel_ideas())
         |> assign_new_social_idea_form()
         |> push_event("close-modal", %{id: "new-social-idea-modal"})}

      {:error, changeset} ->
        {:noreply, assign(socket, :social_idea_form, to_form(changeset, as: "social_channel_idea"))}
    end
  end

  def handle_event("close-new-social-idea-modal", _params, socket) do
    {:noreply, push_event(socket, "close-modal", %{id: "new-social-idea-modal"})}
  end

  def handle_event("close-social-idea-modal", _params, socket) do
    {:noreply, push_event(socket, "close-modal", %{id: "edit-social-idea-modal"})}
  end

  def handle_event("validate_social_idea", %{"social_channel_idea" => params}, socket) do
    form =
      socket.assigns.social_idea
      |> GTM.change_social_channel_idea(params)
      |> Map.put(:action, :validate)
      |> to_form(as: "social_channel_idea")

    {:noreply, assign(socket, :social_idea_form, form)}
  end

  def handle_event("save_social_idea", %{"social_channel_idea" => params}, socket) do
    # Social idea status is derived from whether one of its revisions is approved, so the
    # edit form never sets it directly.
    params = Map.delete(params, "status")

    case GTM.update_social_channel_idea(socket.assigns.social_idea, params, actor: socket.assigns.current_user) do
      {:ok, _idea} ->
        social_idea = GTM.get_social_channel_idea(socket.assigns.social_idea.id)

        {:noreply,
         socket
         |> assign(:social_idea, social_idea)
         |> assign(:page_title, social_idea.title)
         |> assign_social_idea_form(social_idea)
         |> push_event("close-modal", %{id: "edit-social-idea-modal"})}

      {:error, changeset} ->
        {:noreply, assign(socket, :social_idea_form, to_form(changeset, as: "social_channel_idea"))}
    end
  end

  def handle_event("validate_social_post_revision", %{"social_post_revision" => params}, socket) do
    # Reuse the base revision (and its already-derived revision number) from the current
    # form instead of calling change_social_post_revision/2, which issues a MAX query on
    # every keystroke to seed a placeholder number the create path recomputes anyway.
    form =
      socket.assigns.post_revision_form.source.data
      |> GTM.change_existing_social_post_revision(params)
      |> Map.put(:action, :validate)
      |> to_form(as: "social_post_revision")

    {:noreply, assign(socket, :post_revision_form, form)}
  end

  def handle_event("create_social_post_revision", %{"social_post_revision" => params}, socket) do
    params = Map.put(params, "created_by_agent", "dashboard")

    case GTM.create_social_post_revision(socket.assigns.social_idea, params, socket.assigns.current_user,
           actor: socket.assigns.current_user
         ) do
      {:ok, _revision} ->
        social_idea = GTM.get_social_channel_idea(socket.assigns.social_idea.id)

        {:noreply,
         socket
         |> assign(:social_idea, social_idea)
         |> assign_new_social_post_revision_form(social_idea)}

      {:error, changeset} ->
        {:noreply, assign(socket, :post_revision_form, to_form(changeset, as: "social_post_revision"))}
    end
  end

  def handle_event("approve_social_post_revision", %{"id" => id}, socket) do
    case GTM.get_social_post_revision(id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Post revision not found."))}

      revision ->
        case GTM.approve_social_post_revision(revision, actor: socket.assigns.current_user) do
          {:ok, _revision} ->
            social_idea = GTM.get_social_channel_idea(socket.assigns.social_idea.id)

            {:noreply,
             socket
             |> assign(:social_idea, social_idea)
             |> assign(:page_title, social_idea.title)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, gettext("Could not publish the post revision."))}
        end
    end
  end

  def handle_event("delete_social_post_revision", %{"id" => id}, socket) do
    case GTM.get_social_post_revision(id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Post revision not found."))}

      revision ->
        case GTM.delete_social_post_revision(revision, actor: socket.assigns.current_user) do
          {:ok, _deleted} ->
            social_idea = GTM.get_social_channel_idea(socket.assigns.social_idea.id)

            {:noreply,
             socket
             |> assign(:social_idea, social_idea)
             |> assign_new_social_post_revision_form(social_idea)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, gettext("Could not delete the post revision."))}
        end
    end
  end

  def handle_event("delete_social_idea", %{"id" => id}, socket) do
    case GTM.get_social_channel_idea(id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Social idea not found."))}

      idea ->
        case GTM.delete_social_channel_idea(idea, actor: socket.assigns.current_user) do
          {:ok, _deleted} ->
            {:noreply, assign(socket, :social_ideas, GTM.list_social_channel_ideas())}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, gettext("Could not delete the social idea."))}
        end
    end
  end

  defp assign_new_idea_form(socket) do
    assign(
      socket,
      :idea_form,
      to_form(GTM.change_blog_post_idea(%BlogPostIdea{}), as: "blog_post_idea")
    )
  end

  defp assign_idea_form(socket, idea) do
    assign(socket, :idea_form, to_form(GTM.change_blog_post_idea(idea), as: "blog_post_idea"))
  end

  defp assign_comment_form(socket, idea) do
    assign(
      socket,
      :comment_form,
      to_form(GTM.change_blog_post_idea_comment(idea), as: "comment")
    )
  end

  defp assign_new_social_idea_form(socket) do
    assign(
      socket,
      :social_idea_form,
      to_form(GTM.change_social_channel_idea(%SocialChannelIdea{}), as: "social_channel_idea")
    )
  end

  defp assign_social_idea_form(socket, social_idea) do
    assign(
      socket,
      :social_idea_form,
      to_form(GTM.change_social_channel_idea(social_idea), as: "social_channel_idea")
    )
  end

  defp assign_new_social_post_revision_form(socket, social_idea) do
    assign(
      socket,
      :post_revision_form,
      to_form(GTM.change_social_post_revision(social_idea), as: "social_post_revision")
    )
  end

  defp normalize_query_params(params, _live_action), do: params

  attr :ideas, :list, required: true
  attr :idea_form, Form, required: true

  defp content_view(assigns) do
    ~H"""
    <div data-part="header">
      <div data-part="text">
        <h1 data-part="title">{gettext("Content")}</h1>
        <p data-part="description">
          {gettext(
            "Capture blog post ideas with a title and description, then follow up with comments as they take shape."
          )}
        </p>
      </div>

      <div data-part="header-actions">
        <.modal
          id="new-idea-modal"
          title={gettext("Capture an idea")}
          description={
            gettext("Give it a clear title and a short description. You can refine it later.")
          }
          header_type="icon"
          header_size="large"
          on_dismiss="close-new-idea-modal"
          data-part="new-idea-modal"
        >
          <:header_icon><.bulb /></:header_icon>
          <:trigger :let={modal_attrs}>
            <.button label={gettext("New idea")} size="medium" {modal_attrs}>
              <:icon_left><.circle_plus /></:icon_left>
            </.button>
          </:trigger>

          <.form
            id="new-idea-form"
            for={@idea_form}
            phx-change="validate_new_idea"
            phx-submit="create_idea"
          >
            <div data-part="capture-grid">
              <.text_input
                id="new-idea-title-input"
                field={@idea_form[:title]}
                type="basic"
                label={gettext("Title")}
                placeholder={gettext("e.g. How we cut CI times in half with Tuist")}
                required
                show_required
                show_suffix={false}
              />

              <.text_area
                id="new-idea-description-input"
                field={@idea_form[:description]}
                label={gettext("Description")}
                placeholder={gettext("What is the angle, the audience, and the takeaway?")}
                rows={4}
                max_length={4000}
              />
            </div>
          </.form>

          <:footer>
            <.modal_footer>
              <:action>
                <.button
                  label={gettext("Cancel")}
                  variant="secondary"
                  type="button"
                  phx-click="close-new-idea-modal"
                />
              </:action>
              <:action>
                <.button
                  id="new-idea-submit"
                  label={gettext("Add Idea")}
                  form="new-idea-form"
                  type="submit"
                />
              </:action>
            </.modal_footer>
          </:footer>
        </.modal>
      </div>
    </div>

    <section data-part="page-section">
      <.card title={gettext("Ideas")} icon="file_text" data-part="ideas-card">
        <.card_section data-part="ideas-table-section">
          <.table id="gtm-ideas-table" rows={@ideas}>
            <:col :let={idea} label={gettext("Idea")}>
              <div data-part="source-entry">
                <.link navigate={~p"/commercial/gtm/content/#{idea.id}"} data-part="source-title">
                  {idea.title}
                </.link>
                <span :if={idea.description} data-part="source-description">{idea.description}</span>
              </div>
            </:col>
            <:col :let={idea} label={gettext("Status")}>
              <.badge_cell
                label={status_label(idea.status)}
                color={status_color(idea.status)}
                style="light-fill"
              />
            </:col>
            <:col :let={idea} label={gettext("Comments")}>
              <.text_cell label={comment_count_label(idea)} />
            </:col>
            <:col :let={idea} label={gettext("Created")}>
              <.text_cell label={format_datetime(idea.inserted_at)} />
            </:col>
            <:empty_state>
              <.table_empty_state
                icon="bulb"
                title={gettext("No blog post ideas yet")}
                subtitle={
                  gettext(
                    "Use New idea to capture the first one, or ask Atlas in Slack to capture one for you."
                  )
                }
              />
            </:empty_state>
          </.table>
        </.card_section>
      </.card>
    </section>
    """
  end

  attr :idea, :map, required: true
  attr :idea_form, Form, required: true
  attr :comment_form, Form, required: true

  defp idea_view(assigns) do
    ~H"""
    <section data-part="page-section">
      <.button
        id="idea-back-button"
        label={gettext("Content")}
        variant="secondary"
        size="medium"
        navigate={~p"/commercial/gtm/content"}
        data-part="idea-back-button"
      >
        <:icon_left><.arrow_left /></:icon_left>
      </.button>

      <div data-part="idea-header">
        <div data-part="idea-title-group">
          <h1 data-part="idea-title">{@idea.title}</h1>
          <div data-part="idea-badges">
            <.badge label={status_label(@idea.status)} color={status_color(@idea.status)} />
            <span data-part="idea-meta">{format_datetime(@idea.inserted_at)}</span>
          </div>
        </div>
      </div>

      <section data-part="idea-conversation">
        <div data-part="conversation-main">
          <.card title={gettext("Idea Details")} icon="bulb" data-part="idea-details-card">
            <.card_section data-part="idea-details-section">
              <.form
                id="idea-details-form"
                for={@idea_form}
                phx-change="validate_idea"
                phx-submit="save_idea"
              >
                <div data-part="idea-edit-grid">
                  <.text_input
                    id="idea-title-input"
                    field={@idea_form[:title]}
                    type="basic"
                    label={gettext("Title")}
                    required
                    show_required
                    show_suffix={false}
                  />

                  <div data-part="idea-status-field">
                    <.label label={gettext("Status")} required />
                    <.select
                      id="idea-status-select"
                      name="blog_post_idea[status]"
                      label={gettext("Select status")}
                      value={@idea_form[:status].value}
                    >
                      <:item
                        :for={status <- idea_statuses()}
                        value={status}
                        label={status_label(status)}
                      />
                    </.select>
                  </div>

                  <div data-part="idea-edit-grid-full">
                    <.text_area
                      id="idea-description-input"
                      field={@idea_form[:description]}
                      label={gettext("Description")}
                      placeholder={gettext("What is the angle, the audience, and the takeaway?")}
                      rows={5}
                      max_length={4000}
                    />
                  </div>

                  <div data-part="idea-details-actions">
                    <.button label={gettext("Save Changes")} size="small" type="submit" />
                  </div>
                </div>
              </.form>
            </.card_section>
          </.card>

          <.card title={gettext("Follow-ups")} icon="message_circle" data-part="conversation-card">
            <.card_section data-part="conversation-section">
              <div data-part="conversation-header">
                <span data-part="conversation-count">
                  {gettext("%{count} comments", count: length(@idea.comments))}
                </span>
              </div>

              <div id="idea-comments" data-part="comments-list">
                <div
                  :for={comment <- @idea.comments}
                  id={"idea-comment-#{comment.id}"}
                  data-part="comment"
                >
                  <.avatar
                    id={"idea-comment-avatar-#{comment.id}"}
                    size="small"
                    name={comment_author_name(comment)}
                  />
                  <div data-part="comment-content">
                    <div data-part="comment-meta">
                      <span data-part="comment-author">{comment_author_name(comment)}</span>
                      <span data-part="comment-time">{format_datetime(comment.inserted_at)}</span>
                    </div>
                    <div data-part="comment-body">{comment_body_html(comment)}</div>
                  </div>
                </div>

                <div :if={@idea.comments == []} id="idea-comments-empty" data-part="comments-empty">
                  <span data-part="comments-empty-title">{gettext("No follow-ups yet")}</span>
                  <span data-part="comments-empty-subtitle">
                    {gettext("Add angles, references, or open questions as the idea develops.")}
                  </span>
                </div>
              </div>

              <.form id="idea-comment-form" for={@comment_form} phx-submit="add_idea_comment">
                <div data-part="comment-composer">
                  <.text_area
                    id="idea-comment-body"
                    field={@comment_form[:body]}
                    label={gettext("Comment")}
                    rows={4}
                    max_length={4000}
                  />
                  <div data-part="comment-composer-actions">
                    <.button label={gettext("Post Comment")} size="small" type="submit" />
                  </div>
                </div>
              </.form>
            </.card_section>
          </.card>
        </div>

        <aside data-part="conversation-side">
          <.card title={gettext("Properties")} icon="settings" data-part="idea-properties-card">
            <.card_section data-part="idea-properties-section">
              <div data-part="side-section">
                <span data-part="detail-label">{gettext("Status")}</span>
                <span data-part="detail-value">
                  <.badge label={status_label(@idea.status)} color={status_color(@idea.status)} />
                </span>
              </div>

              <div data-part="side-section">
                <span data-part="detail-label">{gettext("Captured by")}</span>
                <span data-part="detail-value">{captured_by(@idea)}</span>
              </div>

              <div data-part="side-section">
                <span data-part="detail-label">{gettext("Created")}</span>
                <span data-part="detail-value">{format_datetime(@idea.inserted_at)}</span>
              </div>

              <div data-part="side-section">
                <span data-part="detail-label">{gettext("Last updated")}</span>
                <span data-part="detail-value">{format_datetime(@idea.updated_at)}</span>
              </div>
            </.card_section>
          </.card>
        </aside>
      </section>
    </section>
    """
  end

  attr :social_ideas, :list, required: true
  attr :social_idea_form, Form, required: true

  defp social_view(assigns) do
    ~H"""
    <div data-part="header">
      <div data-part="text">
        <h1 data-part="title">{gettext("Social")}</h1>
        <p data-part="description">
          {gettext("Capture short-form social ideas and move them from idea to approved.")}
        </p>
      </div>

      <div data-part="header-actions">
        <.modal
          id="new-social-idea-modal"
          title={gettext("Capture a social idea")}
          description={gettext("Give it a clear title and the angle to develop later.")}
          header_type="icon"
          header_size="large"
          on_dismiss="close-new-social-idea-modal"
          data-part="new-social-idea-modal"
        >
          <:header_icon><.message_circle /></:header_icon>
          <:trigger :let={modal_attrs}>
            <.button label={gettext("New social idea")} size="medium" {modal_attrs}>
              <:icon_left><.circle_plus /></:icon_left>
            </.button>
          </:trigger>

          <.form
            id="new-social-idea-form"
            for={@social_idea_form}
            phx-change="validate_new_social_idea"
            phx-submit="create_social_idea"
          >
            <div data-part="capture-grid">
              <.text_input
                id="new-social-idea-title-input"
                field={@social_idea_form[:title]}
                type="basic"
                label={gettext("Title")}
                placeholder={
                  gettext("For example: Turn the cache benchmark into a LinkedIn carousel")
                }
                required
                show_required
                show_suffix={false}
              />

              <.text_area
                id="new-social-idea-description-input"
                field={@social_idea_form[:description]}
                label={gettext("Description")}
                placeholder={gettext("What is the angle, source material, and desired takeaway?")}
                rows={4}
                max_length={4000}
              />
            </div>
          </.form>

          <:footer>
            <.modal_footer>
              <:action>
                <.button
                  label={gettext("Cancel")}
                  variant="secondary"
                  type="button"
                  phx-click="close-new-social-idea-modal"
                />
              </:action>
              <:action>
                <.button
                  id="new-social-idea-submit"
                  label={gettext("Add Social Idea")}
                  form="new-social-idea-form"
                  type="submit"
                />
              </:action>
            </.modal_footer>
          </:footer>
        </.modal>
      </div>
    </div>

    <section data-part="page-section">
      <.card title={gettext("Social ideas")} icon="message_circle" data-part="ideas-card">
        <.card_section data-part="ideas-table-section">
          <.table id="gtm-social-ideas-table" rows={@social_ideas}>
            <:col :let={idea} label={gettext("Idea")}>
              <div data-part="source-entry">
                <.link navigate={~p"/commercial/gtm/social/#{idea.id}"} data-part="source-title">
                  {idea.title}
                </.link>
                <span :if={idea.description} data-part="source-description">{idea.description}</span>
              </div>
            </:col>
            <:col :let={idea} label={gettext("Status")}>
              <.badge_cell
                label={social_status_label(idea.status)}
                color={social_status_color(idea.status)}
                style="light-fill"
              />
            </:col>
            <:col :let={idea} label={gettext("Created")}>
              <.text_cell label={format_datetime(idea.inserted_at)} />
            </:col>
            <:col :let={idea} label="">
              <.button_cell>
                <:button>
                  <div data-part="actions-cell">
                    <.dropdown id={"social-idea-actions-#{idea.id}"} icon_only>
                      <:icon><.dots_vertical /></:icon>

                      <.dropdown_item
                        id={"delete-social-idea-#{idea.id}"}
                        value="delete"
                        label={gettext("Delete")}
                        on_click="delete_social_idea"
                        phx-value-id={idea.id}
                        data-confirm={gettext("Delete this social idea? This cannot be undone.")}
                      >
                        <:left_icon><.trash /></:left_icon>
                      </.dropdown_item>
                    </.dropdown>
                  </div>
                </:button>
              </.button_cell>
            </:col>
            <:empty_state>
              <.table_empty_state
                icon="message_circle"
                title={gettext("No social ideas yet")}
                subtitle={
                  gettext(
                    "Use New social idea to capture the first one, or tag Atlas in Slack to capture one from a thread."
                  )
                }
              />
            </:empty_state>
          </.table>
        </.card_section>
      </.card>
    </section>
    """
  end

  attr :social_idea, :map, required: true
  attr :social_idea_form, Form, required: true
  attr :post_revision_form, Form, required: true

  defp social_idea_view(assigns) do
    ~H"""
    <section data-part="page-section">
      <div data-part="action-buttons">
        <.button
          id="social-idea-back-button"
          label={gettext("Social")}
          variant="secondary"
          size="medium"
          navigate={~p"/commercial/gtm/social"}
          data-part="idea-back-button"
        >
          <:icon_left><.arrow_left /></:icon_left>
        </.button>

        <div data-part="header-actions">
          <.modal
            id="edit-social-idea-modal"
            title={gettext("Edit social idea")}
            description={gettext("Update the headline, status, or working notes.")}
            header_type="icon"
            header_size="large"
            on_dismiss="close-social-idea-modal"
            data-part="edit-social-idea-modal"
          >
            <:header_icon><.pencil /></:header_icon>
            <:trigger :let={modal_attrs}>
              <.button label={gettext("Edit idea")} size="medium" variant="secondary" {modal_attrs}>
                <:icon_left><.pencil /></:icon_left>
              </.button>
            </:trigger>

            <.form
              id="social-idea-details-form"
              for={@social_idea_form}
              phx-change="validate_social_idea"
              phx-submit="save_social_idea"
            >
              <div data-part="capture-grid">
                <.text_input
                  id="social-idea-title-input"
                  field={@social_idea_form[:title]}
                  type="basic"
                  label={gettext("Title")}
                  required
                  show_required
                  show_suffix={false}
                />

                <.text_area
                  id="social-idea-description-input"
                  field={@social_idea_form[:description]}
                  label={gettext("Description")}
                  placeholder={gettext("What is the angle, source material, and desired takeaway?")}
                  rows={5}
                  max_length={4000}
                />
              </div>
            </.form>

            <:footer>
              <.modal_footer>
                <:action>
                  <.button
                    label={gettext("Cancel")}
                    variant="secondary"
                    type="button"
                    phx-click="close-social-idea-modal"
                  />
                </:action>
                <:action>
                  <.button
                    id="social-idea-submit"
                    label={gettext("Save")}
                    form="social-idea-details-form"
                    type="submit"
                  />
                </:action>
              </.modal_footer>
            </:footer>
          </.modal>
        </div>
      </div>

      <div data-part="idea-header">
        <div data-part="idea-title-group">
          <h1 data-part="idea-title">{@social_idea.title}</h1>
          <div data-part="idea-badges">
            <.badge
              label={social_status_label(@social_idea.status)}
              color={social_status_color(@social_idea.status)}
            />
            <span data-part="idea-meta">{format_datetime(@social_idea.inserted_at)}</span>
          </div>
        </div>
      </div>

      <section data-part="social-idea-stack">
        <.card title={gettext("Details")} icon="message_circle" data-part="social-idea-details-card">
          <.card_section data-part="social-details-section">
            <div data-part="social-metadata-grid">
              <div data-part="social-metadata-row">
                <.metadata_item title={gettext("Status")}>
                  <.badge
                    label={social_status_label(@social_idea.status)}
                    color={social_status_color(@social_idea.status)}
                  />
                </.metadata_item>
                <.metadata_item title={gettext("Approved revision")}>
                  {approved_social_post_revision_label(@social_idea)}
                </.metadata_item>
                <.metadata_item title={gettext("Captured by")}>
                  {captured_by(@social_idea)}
                </.metadata_item>
                <.metadata_item title={gettext("Created")}>
                  {format_datetime(@social_idea.inserted_at)}
                </.metadata_item>
                <.metadata_item title={gettext("Last updated")}>
                  {format_datetime(@social_idea.updated_at)}
                </.metadata_item>
              </div>
            </div>

            <div data-part="social-description">
              <div data-part="metadata-title">{gettext("Description")}</div>
              <p :if={@social_idea.description} data-part="idea-description">
                {@social_idea.description}
              </p>
              <p :if={!@social_idea.description} data-part="empty-inline">
                {gettext("No description yet.")}
              </p>
            </div>
          </.card_section>
        </.card>

        <.card
          title={gettext("Revisions")}
          icon="message_circle"
          data-part="post-revisions-card"
        >
          <.card_section data-part="post-revisions-section">
            <div data-part="conversation-header">
              <span data-part="conversation-count">
                {social_post_revision_count_label(@social_idea)}
              </span>
            </div>

            <div id="social-post-revisions" data-part="post-revisions-list">
              <div
                :for={revision <- @social_idea.post_revisions}
                id={"social-post-revision-#{revision.id}"}
                data-part="post-revision-card"
              >
                <div data-part="post-revision-header">
                  <div data-part="post-revision-heading">
                    <div data-part="post-revision-icon">
                      <.message_circle />
                    </div>
                    <div data-part="post-revision-title">
                      <span data-part="post-revision-number">
                        {gettext("Revision %{number}", number: revision.revision_number)}
                      </span>
                      <span data-part="post-revision-meta">
                        {social_post_revision_author_name(revision)} - {format_datetime(
                          revision.inserted_at
                        )}
                      </span>
                    </div>
                  </div>

                  <div data-part="post-revision-actions">
                    <.badge
                      label={social_post_revision_status_label(revision.status)}
                      color={social_post_revision_status_color(revision.status)}
                    />

                    <.dropdown id={"social-post-revision-actions-#{revision.id}"} icon_only>
                      <:icon><.dots_vertical /></:icon>

                      <.dropdown_item
                        :if={revision.status != "approved"}
                        id={"approve-social-post-revision-#{revision.id}"}
                        value="approve"
                        label={gettext("Mark as approved")}
                        on_click="approve_social_post_revision"
                        phx-value-id={revision.id}
                      >
                        <:left_icon><.circle_check /></:left_icon>
                      </.dropdown_item>
                      <.dropdown_item
                        id={"delete-social-post-revision-#{revision.id}"}
                        value="delete"
                        label={gettext("Delete")}
                        on_click="delete_social_post_revision"
                        phx-value-id={revision.id}
                        data-confirm={gettext("Delete this post revision? This cannot be undone.")}
                      >
                        <:left_icon><.trash /></:left_icon>
                      </.dropdown_item>
                    </.dropdown>
                  </div>
                </div>

                <div data-part="post-revision-content">
                  <div data-part="post-revision-body">{revision.body}</div>
                  <div :if={revision.notes} data-part="post-revision-notes">
                    <span data-part="detail-label">{gettext("Notes")}</span>
                    <p>{revision.notes}</p>
                  </div>
                </div>
              </div>

              <div
                :if={@social_idea.post_revisions == []}
                id="social-post-revisions-empty"
                data-part="comments-empty"
              >
                <span data-part="comments-empty-title">{gettext("No revisions yet")}</span>
                <span data-part="comments-empty-subtitle">
                  {gettext("Add a first draft, then keep pushing revisions until one is approved.")}
                </span>
              </div>
            </div>
          </.card_section>

          <.card_section data-part="post-revision-composer-section">
            <.form
              id="social-post-revision-form"
              for={@post_revision_form}
              phx-change="validate_social_post_revision"
              phx-submit="create_social_post_revision"
            >
              <div data-part="post-revision-composer">
                <.text_area
                  id="social-post-revision-body"
                  field={@post_revision_form[:body]}
                  label={gettext("Post text")}
                  placeholder={gettext("Draft the next revision of the social post here.")}
                  rows={6}
                  max_length={8000}
                />

                <.text_area
                  id="social-post-revision-notes"
                  field={@post_revision_form[:notes]}
                  label={gettext("Notes")}
                  placeholder={gettext("What changed, or what should the next revision improve?")}
                  rows={3}
                  max_length={2000}
                />

                <div data-part="post-revision-composer-actions">
                  <.button
                    id="social-post-revision-submit"
                    label={gettext("Add revision")}
                    type="submit"
                  >
                    <:icon_left><.circle_plus /></:icon_left>
                  </.button>
                </div>
              </div>
            </.form>
          </.card_section>
        </.card>
      </section>
    </section>
    """
  end

  defp idea_statuses, do: BlogPostIdea.statuses()

  defp status_label("idea"), do: gettext("Idea")
  defp status_label("in_progress"), do: gettext("In progress")
  defp status_label("published"), do: gettext("Published")
  defp status_label(_status), do: gettext("Unknown")

  defp status_color("published"), do: "success"
  defp status_color("in_progress"), do: "warning"
  defp status_color(_status), do: "neutral"

  defp social_status_label("idea"), do: gettext("Idea")
  defp social_status_label("approved"), do: gettext("Approved")
  defp social_status_label(_status), do: gettext("Unknown")

  defp social_status_color("approved"), do: "success"
  defp social_status_color(_status), do: "neutral"

  defp social_post_revision_status_label("draft"), do: gettext("Draft")
  defp social_post_revision_status_label("approved"), do: gettext("Approved")
  defp social_post_revision_status_label(_status), do: gettext("Unknown")

  defp social_post_revision_status_color("approved"), do: "success"
  defp social_post_revision_status_color(_status), do: "neutral"

  defp comment_count_label(idea) do
    gettext("%{count}", count: length(idea.comments))
  end

  defp social_post_revision_count_label(%{post_revisions: revisions}) when is_list(revisions) do
    count = length(revisions)
    ngettext("%{count} revision", "%{count} revisions", count, count: count)
  end

  defp social_post_revision_count_label(_idea), do: gettext("0 revisions")

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp metadata_item(assigns) do
    ~H"""
    <div data-part="metadata">
      <div data-part="metadata-title">{@title}</div>
      <div data-part="metadata-value">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  defp approved_social_post_revision_label(%{post_revisions: revisions}) when is_list(revisions) do
    revisions
    |> Enum.find(&(&1.status == "approved"))
    |> case do
      nil -> gettext("None")
      revision -> gettext("Revision %{number}", number: revision.revision_number)
    end
  end

  defp approved_social_post_revision_label(_idea), do: gettext("None")

  defp captured_by(%{author: %{name: name}}) when is_binary(name) and name != "", do: name
  defp captured_by(%{author: %{email: email}}) when is_binary(email) and email != "", do: email
  defp captured_by(%{created_by_agent: agent}) when is_binary(agent) and agent != "", do: agent
  defp captured_by(_idea), do: gettext("Unknown")

  defp comment_body_html(%{body: body}) when is_binary(body) and body != "" do
    body
    |> MDEx.to_html!(sanitize: MDEx.Document.default_sanitize_options())
    |> raw()
  end

  defp comment_body_html(_comment), do: nil

  defp comment_author_name(%{author: %{name: name}}) when is_binary(name) and name != "", do: name
  defp comment_author_name(%{author: %{email: email}}) when is_binary(email) and email != "", do: email
  defp comment_author_name(%{author_name: name}) when is_binary(name) and name != "", do: name
  defp comment_author_name(_comment), do: gettext("Atlas")

  defp social_post_revision_author_name(%{author: %{name: name}}) when is_binary(name) and name != "", do: name
  defp social_post_revision_author_name(%{author: %{email: email}}) when is_binary(email) and email != "", do: email
  defp social_post_revision_author_name(%{created_by_agent: agent}) when is_binary(agent) and agent != "", do: agent
  defp social_post_revision_author_name(_revision), do: gettext("Atlas")

  defp format_datetime(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %d, %Y")
  defp format_datetime(%NaiveDateTime{} = datetime), do: Calendar.strftime(datetime, "%b %d, %Y")
  defp format_datetime(_datetime), do: "-"
end
