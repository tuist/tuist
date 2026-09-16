defmodule AtlasWeb.SupportLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []
  import Noora.CheckboxControl
  import Noora.Filter

  alias Atlas.Support
  alias Atlas.Support.ReplyContent
  alias Atlas.Users
  alias Atlas.Users.User
  alias AtlasWeb.Utilities.Avatar
  alias AtlasWeb.Utilities.Query
  alias Noora.Filter

  @page_size 50
  @max_total_attachment_size 15_000_000

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Support"))
     |> assign(:available_filters, define_filters())
     |> assign(:composer_form, composer_form())
     |> assign(:composer_mode, :reply)
     |> assign(:owner_form, owner_form(nil))
     |> assign(:threads_empty?, true)
     |> assign(:users, [])
     |> allow_upload(:reply_attachment,
       accept: :any,
       max_entries: 5,
       max_file_size: 5_000_000,
       auto_upload: true
     )}
  end

  def handle_params(params, uri, socket) do
    case socket.assigns.live_action do
      :index -> {:noreply, assign_queue(socket, params, uri)}
      :show -> {:noreply, assign_thread(socket, params["id"])}
    end
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    params =
      socket
      |> queue_params()
      |> Map.put("q", String.trim(query))
      |> Map.delete("page")

    {:noreply, push_patch(socket, to: ~p"/support?#{params}", replace: true)}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params =
      filter_id
      |> Filter.Operations.add_filter_to_query(socket)
      |> Map.delete("page")

    {:noreply,
     socket
     |> push_patch(to: ~p"/support?#{updated_params}")
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_params =
      params
      |> Filter.Operations.update_filters_in_query(socket)
      |> Map.delete("page")

    {:noreply,
     socket
     |> push_patch(to: ~p"/support?#{updated_params}")
     |> push_event("close-dropdown", %{id: "all", all: true})}
  end

  def handle_event("set_status", %{"thread_id" => thread_id, "status" => status}, socket) do
    case Support.set_status(thread_id, status, socket.assigns.current_user) do
      {:ok, _thread} ->
        {:noreply,
         socket
         |> put_flash(:info, status_message(status))
         |> push_patch(to: ~p"/support?#{queue_params(socket)}", replace: true)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not update the conversation."))}
    end
  end

  def handle_event("set_status", %{"status" => status}, socket) do
    case Support.set_status(socket.assigns.thread, status, socket.assigns.current_user) do
      {:ok, thread} ->
        {:noreply,
         socket
         |> assign_thread(thread.id)
         |> put_flash(:info, status_message(status))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not update the conversation."))}
    end
  end

  def handle_event("assign_to_self", %{"thread_id" => thread_id}, socket) do
    case Support.assign(thread_id, socket.assigns.current_user.id, socket.assigns.current_user) do
      {:ok, _thread} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Conversation assigned."))
         |> push_patch(to: ~p"/support?#{queue_params(socket)}", replace: true)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not assign the conversation."))}
    end
  end

  def handle_event("assign_to_self", _params, socket) do
    assign_owner(socket, socket.assigns.current_user.id)
  end

  def handle_event("assign", %{"assignment" => %{"owner_id" => owner_id}}, socket) do
    assign_owner(socket, owner_id)
  end

  def handle_event("assign", %{"value" => [owner_id]}, socket) when is_binary(owner_id) do
    assign_owner(socket, owner_id)
  end

  def handle_event("assign", %{"value" => []}, socket), do: {:noreply, socket}

  def handle_event("assign", %{"value" => owner_id}, socket) when is_binary(owner_id) do
    assign_owner(socket, owner_id)
  end

  def handle_event("set_composer_mode", %{"mode" => "reply"}, socket) do
    {:noreply, assign(socket, :composer_mode, :reply)}
  end

  def handle_event("set_composer_mode", %{"mode" => "note"}, socket) do
    {:noreply, assign(socket, :composer_mode, :note)}
  end

  def handle_event("validate_composer", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_reply_attachment", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :reply_attachment, ref)}
  end

  def handle_event("submit_composer", %{"composer" => params}, socket) do
    case socket.assigns.composer_mode do
      :note ->
        submit_note(socket, params)

      :reply ->
        submit_reply_composer(socket, params)
    end
  end

  defp submit_reply_composer(socket, params) do
    case validate_reply_composer(params, socket.assigns.uploads.reply_attachment) do
      :ok ->
        case consume_reply_attachments(socket) do
          {:ok, attachments} ->
            submit_reply(socket, Map.put(params, "attachments", attachments))

          {:error, :upload_in_progress} ->
            {:noreply, put_flash(socket, :error, gettext("Wait for attachments to finish uploading."))}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, gettext("Could not read the selected attachments."))}
        end

      {:error, :body_required} ->
        {:noreply, put_flash(socket, :error, gettext("Write a reply before sending."))}

      {:error, :attachment_invalid} ->
        {:noreply, put_flash(socket, :error, gettext("Remove or replace the invalid attachment."))}

      {:error, :attachments_too_large} ->
        {:noreply, put_flash(socket, :error, gettext("Attachments cannot exceed 15 megabytes in total."))}

      {:error, :upload_in_progress} ->
        {:noreply, put_flash(socket, :error, gettext("Wait for attachments to finish uploading."))}
    end
  end

  defp submit_reply(socket, params) do
    case Support.reply(socket.assigns.thread, params, socket.assigns.current_user) do
      {:ok, %{message: message}} ->
        {:noreply,
         socket
         |> put_flash(:info, reply_confirmation(message))
         |> push_navigate(to: ~p"/support/#{socket.assigns.thread.id}")}

      {:error, :body_required} ->
        {:noreply, put_flash(socket, :error, gettext("Write a reply before sending."))}

      {:error, :chat_reply_attachments_unsupported} ->
        {:noreply,
         put_flash(socket, :error, gettext("Attachments can be sent after the customer confirms their email."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not queue the reply."))}
    end
  end

  defp submit_note(socket, params) do
    case Support.add_note(socket.assigns.thread, params, socket.assigns.current_user) do
      {:ok, _note} ->
        {:noreply,
         socket
         |> assign_thread(socket.assigns.thread.id)
         |> put_flash(:info, gettext("Private note added."))}

      {:error, :body_required} ->
        {:noreply, put_flash(socket, :error, gettext("Write a note before adding it."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not add the private note."))}
    end
  end

  def render(assigns) do
    ~H"""
    <div id={@page_id} data-part="support-page">
      <%= case @live_action do %>
        <% :index -> %>
          <.queue_view
            threads={@streams.threads}
            threads_empty?={@threads_empty?}
            counts={@counts}
            selected_status={@selected_status}
            available_filters={@available_filters}
            active_filters={@active_filters}
            search_form={@search_form}
            threads_meta={@threads_meta}
            current_page={@current_page}
            current_user={@current_user}
          />
        <% :show -> %>
          <.thread_view
            thread={@thread}
            messages={@streams.messages}
            composer_form={@composer_form}
            composer_mode={@composer_mode}
            unverified_chat?={unverified_chat?(@thread)}
            owner_form={@owner_form}
            users={@users}
            current_user={@current_user}
            uploads={@uploads}
          />
      <% end %>
    </div>
    """
  end

  attr :threads, :any, required: true
  attr :threads_empty?, :boolean, required: true
  attr :counts, :map, required: true
  attr :selected_status, :string, required: true
  attr :available_filters, :list, required: true
  attr :active_filters, :list, required: true
  attr :search_form, :map, required: true
  attr :threads_meta, :map, required: true
  attr :current_page, :integer, required: true
  attr :current_user, :map, required: true

  defp queue_view(assigns) do
    ~H"""
    <div data-part="header">
      <div data-part="text">
        <h1 data-part="title">{gettext("Support")}</h1>
        <p data-part="description">
          {gettext("Shared customer conversations received at contact@tuist.dev.")}
        </p>
      </div>
    </div>

    <.tab_menu_horizontal
      id="support-queue-tabs"
      data-part="queue-tabs"
      aria-label={gettext("Conversation status")}
    >
      <.tab_menu_horizontal_item
        id="support-needs-reply-tab"
        patch={support_path("open", @active_filters)}
        label={gettext("Needs reply")}
        selected={@selected_status == "open"}
      >
        <:icon_right>
          <.badge
            id="support-needs-reply-count"
            label={Integer.to_string(@counts["open"])}
            color="attention"
            style="light-fill"
          />
        </:icon_right>
      </.tab_menu_horizontal_item>
      <.tab_menu_horizontal_item
        id="support-waiting-tab"
        patch={support_path("waiting", @active_filters)}
        label={gettext("Waiting")}
        selected={@selected_status == "waiting"}
      >
        <:icon_right>
          <.badge
            id="support-waiting-count"
            label={Integer.to_string(@counts["waiting"])}
            color="information"
            style="light-fill"
          />
        </:icon_right>
      </.tab_menu_horizontal_item>
      <.tab_menu_horizontal_item
        id="support-resolved-tab"
        patch={support_path("resolved", @active_filters)}
        label={gettext("Resolved")}
        selected={@selected_status == "resolved"}
      >
        <:icon_right>
          <.badge
            id="support-resolved-count"
            label={Integer.to_string(@counts["resolved"])}
            color="success"
            style="light-fill"
          />
        </:icon_right>
      </.tab_menu_horizontal_item>
      <.tab_menu_horizontal_item
        id="support-all-tab"
        patch={support_path("all", @active_filters)}
        label={gettext("All conversations")}
        selected={@selected_status == "all"}
      />
    </.tab_menu_horizontal>

    <.card title={gettext("Conversations")} icon="message_circle" data-part="threads-card">
      <.card_section data-part="threads-table-section">
        <div data-part="filters">
          <.filter_dropdown
            id="support-filters-dropdown"
            available_filters={@available_filters}
            active_filters={@active_filters}
          />

          <div data-part="search">
            <.form
              for={@search_form}
              id="support-search-form"
              phx-change="search"
            >
              <.text_input
                id="support-search-input"
                field={@search_form[:query]}
                type="search"
                show_suffix={false}
                placeholder={gettext("Search sender or subject")}
              />
            </.form>
          </div>
        </div>

        <div :if={@active_filters != []} data-part="active-filters">
          <.active_filter :for={filter <- @active_filters} filter={filter} />
        </div>

        <.thread_table
          threads={@threads}
          threads_empty?={@threads_empty?}
          current_user={@current_user}
        />

        <.pagination_group
          :if={@threads_meta.total_pages > 1}
          current_page={@current_page}
          number_of_pages={@threads_meta.total_pages}
          page_patch={fn page -> support_path(@selected_status, @active_filters, page: page) end}
        />
      </.card_section>
    </.card>
    """
  end

  attr :threads, :any, required: true
  attr :threads_empty?, :boolean, required: true
  attr :current_user, :map, required: true

  defp thread_table(assigns) do
    ~H"""
    <div id="support-threads-table" class="noora-table" phx-hook="NooraTable">
      <div data-part="scroll-container">
        <table>
          <thead>
            <tr>
              <th>{gettext("Conversation")}</th>
              <th>{gettext("Assignee")}</th>
              <th>{gettext("Status")}</th>
              <th>{gettext("Updated")}</th>
              <th>{gettext("Actions")}</th>
            </tr>
          </thead>
          <tbody :if={@threads_empty?} id="support-threads-table-empty-body">
            <tr>
              <td colspan="5">
                <div id="support-threads-empty">
                  <.table_empty_state
                    icon="message_circle"
                    title={gettext("No conversations here")}
                    subtitle={
                      gettext("New messages sent to contact@tuist.dev will appear in this queue.")
                    }
                  />
                </div>
              </td>
            </tr>
          </tbody>
          <tbody :if={!@threads_empty?} id="support-threads-table-body" phx-update="stream">
            <tr :for={{dom_id, thread} <- @threads} id={dom_id} data-part="thread-row">
              <td data-selectable>
                <.link navigate={~p"/support/#{thread.id}"} data-part="row-link">
                  <.text_and_description_cell
                    label={thread.subject || gettext("Untitled conversation")}
                    description={customer_label(thread)}
                    secondary_description={
                      (thread.account && thread.account.name) || thread.customer_email
                    }
                  >
                    <:image>
                      <.avatar
                        id={"support-thread-avatar-#{thread.id}"}
                        size="small"
                        name={customer_label(thread)}
                        image_href={Avatar.gravatar_url(thread.customer_email)}
                      />
                    </:image>
                  </.text_and_description_cell>
                </.link>
              </td>
              <td>
                <.text_and_description_cell
                  label={owner_label(thread.owner)}
                  description={thread.owner && thread.owner.email}
                />
              </td>
              <td>
                <.badge_cell
                  label={status_label(thread.status)}
                  color={status_color(thread.status)}
                  style="light-fill"
                />
              </td>
              <td>
                <.text_and_description_cell
                  label={relative_time(thread.last_message_at)}
                  description={format_datetime(thread.last_message_at)}
                />
              </td>
              <td>
                <div data-part="cell" data-type="button">
                  <div data-part="thread-actions-cell">
                    <.button_dropdown
                      id={"support-thread-actions-#{thread.id}"}
                      label={primary_action_label(thread.status)}
                      size="medium"
                      align="end"
                      phx-click="set_status"
                      phx-value-thread_id={thread.id}
                      phx-value-status={primary_action_status(thread.status)}
                    >
                      <:icon_left><.icon name={primary_action_icon(thread.status)} /></:icon_left>
                      <.dropdown_item
                        :if={!thread.owner_id || thread.owner_id != @current_user.id}
                        id={"support-thread-assign-to-self-#{thread.id}"}
                        value={"assign-to-me-#{thread.id}"}
                        label={gettext("Assign to me")}
                        on_click="assign_to_self"
                        phx-value-thread_id={thread.id}
                      >
                        <:left_icon><.user /></:left_icon>
                      </.dropdown_item>
                    </.button_dropdown>
                  </div>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <div data-part="scrollbar" aria-hidden="true">
        <div data-part="scrollbar-content"></div>
      </div>
      <div data-part="overlay-scrollbar" aria-hidden="true">
        <div data-part="overlay-thumb"></div>
      </div>
    </div>
    """
  end

  attr :thread, :map, required: true
  attr :messages, :any, required: true
  attr :composer_form, :map, required: true
  attr :composer_mode, :atom, required: true
  attr :unverified_chat?, :boolean, required: true
  attr :owner_form, :map, required: true
  attr :users, :list, required: true
  attr :current_user, :map, required: true
  attr :uploads, :map, required: true

  defp thread_view(assigns) do
    ~H"""
    <.button
      id="support-back"
      label={gettext("Support")}
      variant="secondary"
      size="medium"
      navigate={~p"/support"}
      data-part="back-button"
    >
      <:icon_left><.icon name="arrow_left" /></:icon_left>
    </.button>

    <div data-part="thread-header">
      <div data-part="thread-heading">
        <h1 data-part="title">{@thread.subject || gettext("Untitled conversation")}</h1>
      </div>

      <div data-part="thread-actions">
        <.button
          :if={@thread.owner_id != @current_user.id}
          id="support-assign-to-self"
          label={gettext("Assign to me")}
          variant="secondary"
          size="medium"
          type="button"
          phx-click="assign_to_self"
        />
        <.button
          :if={@thread.status != "resolved"}
          id="support-resolve"
          label={gettext("Resolve")}
          size="medium"
          type="button"
          phx-click="set_status"
          phx-value-status="resolved"
        >
          <:icon_left><.icon name="check" /></:icon_left>
        </.button>
        <.button
          :if={@thread.status == "resolved"}
          id="support-reopen"
          label={gettext("Reopen")}
          variant="secondary"
          size="medium"
          type="button"
          phx-click="set_status"
          phx-value-status="open"
        />
      </div>
    </div>

    <section data-part="thread-layout">
      <div data-part="thread-main">
        <.card title={gettext("Conversation")} icon="message_circle" data-part="conversation-card">
          <.card_section data-part="messages-section">
            <div
              :if={unverified_chat?(@thread)}
              id="support-chat-email-unverified"
              data-part="email-verification"
            >
              <.badge
                label={gettext("Email unverified")}
                color="attention"
                style="light-fill"
                data-part="email-verification-badge"
              />
              <p data-part="email-verification-copy">
                {gettext(
                  "Replies will appear in this chat, but are not emailed until the customer confirms their email."
                )}
              </p>
            </div>
            <div id="support-thread-messages" phx-update="stream" data-part="message-list">
              <article
                :for={{dom_id, message} <- @messages}
                id={dom_id}
                data-part="message"
                data-kind={message.kind}
              >
                <div data-part="message-header">
                  <div data-part="message-author">
                    <.avatar
                      id={"support-message-avatar-#{message.id}"}
                      size="small"
                      name={message_author(message)}
                      image_href={message_avatar(message)}
                      data-part="message-avatar"
                    />
                    <div data-part="message-author-details">
                      <span data-part="name">{message_author(message)}</span>
                      <div data-part="message-meta">
                        <.badge
                          :if={message.kind == "note"}
                          data-part="private-badge"
                          label={gettext("Private")}
                          color="primary"
                          style="light-fill"
                        >
                          <:icon><.icon name="lock" /></:icon>
                        </.badge>
                        <span :if={message.kind != "note"} data-part="role">
                          {message_role(message)}
                        </span>
                      </div>
                    </div>
                  </div>
                  <span data-part="time">{format_datetime(message.occurred_at)}</span>
                </div>
                <%= if message.kind == "inbound" && message.inbox_email_id do %>
                  <iframe
                    id={"support-message-original-#{message.id}"}
                    title={gettext("Original email")}
                    src={~p"/support/messages/#{message.id}/original"}
                    sandbox="allow-same-origin"
                    referrerpolicy="no-referrer"
                    phx-hook="OriginalEmailPreview"
                    phx-update="ignore"
                    data-part="original-email-preview"
                  >
                  </iframe>
                <% else %>
                  <div data-part="message-body">{message_body(message)}</div>
                <% end %>
                <div :if={inline_attachment_ids(message) != []} data-part="inline-attachments">
                  <img
                    :for={content_id <- inline_attachment_ids(message)}
                    src={inline_attachment_url(message, content_id)}
                    alt={gettext("Inline email attachment")}
                    data-part="inline-attachment"
                  />
                </div>
                <div :if={message.kind == "outbound"} data-part="delivery">
                  {delivery_label(message)}
                </div>
                <.link_button
                  :if={message.kind == "inbound" && message.inbox_email_id}
                  href={~p"/support/messages/#{message.id}/original"}
                  label={gettext("Open original email")}
                  size="small"
                  target="_blank"
                  rel="noreferrer"
                  data-part="original-email-link"
                >
                  <:icon_right><.icon name="external_link" /></:icon_right>
                </.link_button>
                <div :if={attachments(message) != []} data-part="attachments">
                  <a
                    :for={attachment <- attachments(message)}
                    href={attachment_download_url(message, attachment)}
                    data-part="attachment"
                  >
                    <.icon name="file" /> {attachment["filename"]}
                  </a>
                </div>
              </article>
            </div>
          </.card_section>
        </.card>

        <.card
          title={composer_title(@composer_mode)}
          icon={composer_icon(@composer_mode)}
          data-part="composer-card"
        >
          <.card_section data-part="composer-section">
            <.form
              id="support-composer-form"
              for={@composer_form}
              phx-change="validate_composer"
              phx-submit="submit_composer"
              data-part="composer-form"
            >
              <div data-part="composer-type">
                <.label label={gettext("Response type")} />
                <.button_group
                  id="support-composer-mode"
                  size="small"
                  aria-label={gettext("Response type")}
                  data-part="composer-mode"
                >
                  <.button_group_item
                    id="support-composer-mode-reply"
                    label={gettext("Reply")}
                    type="button"
                    phx-click="set_composer_mode"
                    phx-value-mode="reply"
                    data-selected={@composer_mode == :reply}
                    aria-pressed={to_string(@composer_mode == :reply)}
                  >
                    <:icon_left><.icon name="message_circle" /></:icon_left>
                  </.button_group_item>
                  <.button_group_item
                    id="support-composer-mode-note"
                    label={gettext("Private note")}
                    type="button"
                    phx-click="set_composer_mode"
                    phx-value-mode="note"
                    data-selected={@composer_mode == :note}
                    aria-pressed={to_string(@composer_mode == :note)}
                  >
                    <:icon_left><.icon name="lock" /></:icon_left>
                  </.button_group_item>
                </.button_group>
              </div>

              <.text_area
                id="support-composer-body"
                field={@composer_form[:body]}
                placeholder={composer_placeholder(@composer_mode)}
                hint={composer_hint(@composer_mode)}
                rows={5}
                max_length={10_000}
                show_character_count={false}
              />
              <div
                :if={@composer_mode == :reply and !@unverified_chat?}
                data-part="composer-attachments"
              >
                <label
                  id="support-composer-add-attachment"
                  class="noora-button"
                  data-part="upload-button"
                  data-variant="secondary"
                  data-size="small"
                >
                  <.live_file_input
                    upload={@uploads.reply_attachment}
                    id="support-composer-attachment-input"
                  />
                  <.icon name="file" />
                  <span>{gettext("Attach files")}</span>
                </label>
                <div
                  :if={
                    @uploads.reply_attachment.entries != [] or
                      upload_errors(@uploads.reply_attachment) != []
                  }
                  id="support-composer-attachments-status"
                  data-part="upload-status"
                >
                  <div :for={entry <- @uploads.reply_attachment.entries} data-part="upload-entry">
                    <span>{entry.client_name}</span>
                    <.button
                      id={"support-composer-remove-attachment-#{entry.ref}"}
                      label={gettext("Remove")}
                      variant="secondary"
                      size="small"
                      type="button"
                      phx-click="cancel_reply_attachment"
                      phx-value-ref={entry.ref}
                    />
                    <span
                      :for={error <- upload_errors(@uploads.reply_attachment, entry)}
                      data-part="upload-error"
                    >
                      {attachment_upload_error(error)}
                    </span>
                  </div>
                  <span
                    :for={error <- upload_errors(@uploads.reply_attachment)}
                    data-part="upload-error"
                  >
                    {attachment_upload_error(error)}
                  </span>
                </div>
              </div>
              <div data-part="composer-actions">
                <div
                  :if={@composer_mode == :reply and !@unverified_chat?}
                  id="support-reply-all"
                  class="noora-checkbox"
                  phx-hook="NooraCheckbox"
                  data-part="reply-all-control"
                >
                  <label data-part="root">
                    <input type="hidden" name={@composer_form[:reply_all].name} value="false" />
                    <input
                      id="support-reply-all-input"
                      type="checkbox"
                      name={@composer_form[:reply_all].name}
                      checked={@composer_form[:reply_all].value in [true, "true", "on", "1"]}
                      data-peer
                      data-part="hidden-input"
                    />
                    <.checkbox_control data-part="control" />
                    <span data-part="label">{gettext("Reply all")}</span>
                  </label>
                </div>
                <.button
                  id="support-composer-submit"
                  label={composer_submit_label(@composer_mode)}
                  type="submit"
                />
              </div>
            </.form>
          </.card_section>
        </.card>
      </div>

      <aside data-part="thread-side">
        <.card title={gettext("Details")} icon="settings" data-part="conversation-details-card">
          <.card_section data-part="details-section">
            <div data-part="detail-row">
              <span data-part="detail-label">{gettext("Status")}</span>
              <.badge
                label={status_label(@thread.status)}
                color={status_color(@thread.status)}
                style="light-fill"
              />
            </div>
            <div data-part="detail-row">
              <span data-part="detail-label">{gettext("Email")}</span>
              <span data-part="detail-value">{@thread.customer_email}</span>
            </div>
            <div data-part="detail-row">
              <span data-part="detail-label">{gettext("Account")}</span>
              <.link
                :if={@thread.account}
                navigate={~p"/sales/accounts/#{@thread.account.id}"}
                data-part="account-link"
              >
                {@thread.account.name}
              </.link>
              <span :if={!@thread.account} data-part="detail-value">
                {gettext("Unmatched contact")}
              </span>
            </div>
            <.form id="support-assignment-form" for={@owner_form} data-part="owner-field">
              <.label label={gettext("Assignee")} />
              <.select
                id="support-owner"
                field={@owner_form[:owner_id]}
                label={gettext("Select assignee")}
                on_value_change="assign"
              >
                <:item
                  :for={user <- @users}
                  value={user.id}
                  label={user.name || user.email}
                />
              </.select>
            </.form>
          </.card_section>
        </.card>
      </aside>
    </section>
    """
  end

  defp assign_queue(socket, params, _uri) do
    params = Query.copy_legacy_filters(params, ["owner"])
    status = normalize_status(params["status"])

    active_filters =
      Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)

    owner = owner_filter_value(active_filters) || normalize_owner(params["owner"])
    query = params["q"] || ""
    page = Query.parse_page(params["page"])
    owner_id = if owner == "mine", do: socket.assigns.current_user.id

    {threads, threads_meta} =
      Support.list_threads(
        status: if(status != "all", do: status),
        owner_id: owner_id,
        query: query,
        page: page,
        page_size: @page_size
      )

    socket
    |> assign(:page_id, "support")
    |> assign(:page_title, gettext("Support"))
    |> assign(:selected_status, status)
    |> assign(:active_filters, active_filters)
    |> assign(:counts, Support.list_thread_counts(owner_id))
    |> assign(:threads_empty?, threads == [])
    |> assign(:threads_meta, threads_meta)
    |> assign(:current_page, page)
    |> assign(:search_form, to_form(%{"query" => query}, as: :search))
    |> assign(:uri, URI.new!("?" <> URI.encode_query(params)))
    |> stream(:threads, threads, reset: true)
  end

  defp assign_thread(socket, id) do
    case Support.get_thread(id) do
      nil ->
        socket
        |> put_flash(:error, gettext("Conversation not found."))
        |> push_navigate(to: ~p"/support")

      thread ->
        socket
        |> assign_thread_record(thread)
        |> assign(:users, Users.list_users())
    end
  end

  defp assign_thread_record(socket, thread) do
    socket
    |> assign(:page_id, "support-thread")
    |> assign(:page_title, thread.subject || gettext("Support"))
    |> assign(:thread, thread)
    |> assign(:composer_form, composer_form())
    |> assign(:composer_mode, :reply)
    |> assign(:owner_form, owner_form(thread.owner_id))
    |> stream(:messages, thread.messages, reset: true)
  end

  defp assign_owner(socket, owner_id) do
    case Support.assign(socket.assigns.thread, owner_id, socket.assigns.current_user) do
      {:ok, thread} ->
        {:noreply,
         socket
         |> assign_thread(thread.id)
         |> put_flash(:info, gettext("Conversation assigned."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not assign the conversation."))}
    end
  end

  defp composer_form, do: to_form(%{"body" => "", "reply_all" => false}, as: :composer)
  defp owner_form(owner_id), do: to_form(%{"owner_id" => owner_id || ""}, as: :assignment)

  defp composer_title(:reply), do: gettext("Reply")
  defp composer_title(:note), do: gettext("Private note")
  defp composer_icon(:reply), do: "message_circle"
  defp composer_icon(:note), do: "lock"
  defp composer_placeholder(:reply), do: gettext("Write a reply to the customer")
  defp composer_placeholder(:note), do: gettext("Write a private note for the team")
  defp composer_hint(:reply), do: nil
  defp composer_hint(:note), do: gettext("Visible only to the team")
  defp composer_submit_label(:reply), do: gettext("Send reply")
  defp composer_submit_label(:note), do: gettext("Add private note")

  defp queue_params(socket) do
    socket.assigns.uri.query
    |> Query.query_params()
  end

  defp support_path(status, active_filters, opts \\ []) do
    params =
      %{"status" => status}
      |> Map.merge(Filter.Operations.encode_filters_to_query(active_filters))
      |> Map.merge(Map.new(opts))

    ~p"/support?#{params}"
  end

  defp normalize_status(status) when status in ["open", "waiting", "resolved", "all"], do: status
  defp normalize_status(_status), do: "open"
  defp normalize_owner("mine"), do: "mine"
  defp normalize_owner(_owner), do: "all"

  defp define_filters do
    [
      %Filter.Filter{
        id: "owner",
        display_name: gettext("Owner"),
        type: :option,
        options: ["mine"],
        options_display_names: %{"mine" => gettext("Me")},
        operator: :==,
        value: nil
      }
    ]
  end

  defp owner_filter_value(filters) do
    case Enum.find(filters, &(&1.id == "owner" && &1.value == "mine")) do
      nil -> nil
      _filter -> "mine"
    end
  end

  defp customer_label(thread), do: thread.customer_name || thread.customer_email
  defp unverified_chat?(thread), do: thread.metadata["channel"] == "chat" and thread.metadata["email_verified"] != true
  defp owner_label(nil), do: gettext("Unassigned")
  defp owner_label(owner), do: owner.name || owner.email
  defp status_label("open"), do: gettext("Needs reply")
  defp status_label("waiting"), do: gettext("Waiting")
  defp status_label("resolved"), do: gettext("Resolved")
  defp status_label(_status), do: gettext("Unknown")
  defp status_color("open"), do: "attention"
  defp status_color("waiting"), do: "information"
  defp status_color("resolved"), do: "success"
  defp status_color(_status), do: "neutral"
  defp message_author(%{kind: "note", author: author}), do: (author && (author.name || author.email)) || gettext("Team")

  defp message_author(%{kind: "outbound", author: author}),
    do: (author && (author.name || author.email)) || gettext("Tuist")

  defp message_author(message), do: message.sender_name || message.sender_email
  defp message_role(%{kind: "note"}), do: gettext("Private note")
  defp message_role(%{kind: "outbound"}), do: gettext("Tuist")
  defp message_role(_message), do: gettext("Customer")
  defp message_body(%{kind: "inbound", body: body}), do: ReplyContent.visible(body)
  defp message_body(%{body: body}), do: body
  defp inline_attachment_ids(%{kind: "inbound", body: body}), do: ReplyContent.inline_attachment_ids(body)
  defp inline_attachment_ids(_message), do: []

  defp inline_attachment_url(message, content_id) do
    ~p"/support/messages/#{message.id}/attachments?#{[content_id: content_id]}"
  end

  defp attachment_download_url(message, attachment) do
    case Map.get(attachment, "checksum_sha256") do
      checksum when is_binary(checksum) ->
        ~p"/support/messages/#{message.id}/download?#{[checksum: checksum]}"

      _ ->
        ~p"/support/messages/#{message.id}/download/#{attachment["filename"]}"
    end
  end

  defp message_avatar(%{kind: "inbound", sender_email: email}), do: Avatar.gravatar_url(email)
  defp message_avatar(%{author: author}), do: author && User.avatar_url(author)

  defp reply_confirmation(%{metadata: %{"delivery_channel" => "chat"}}),
    do: gettext("Reply sent in chat. It was not emailed because the address is unverified.")

  defp reply_confirmation(_message), do: gettext("Reply queued for delivery.")

  defp delivery_label(%{metadata: %{"delivery_channel" => "chat"}}), do: gettext("Delivered in chat")

  defp delivery_label(%{delivery_status: "queued"}), do: gettext("Sending…")
  defp delivery_label(%{delivery_status: "sending"}), do: gettext("Sending…")
  defp delivery_label(%{delivery_status: "delivered"}), do: gettext("Delivered")
  defp delivery_label(%{delivery_status: "failed"}), do: gettext("Delivery failed")
  defp delivery_label(_message), do: nil

  defp attachments(message) do
    message.metadata
    |> Map.get("attachments", [])
    |> List.wrap()
    |> Enum.reject(&inline_attachment?/1)
  end

  defp inline_attachment?(%{"content_id" => content_id}) when is_binary(content_id), do: true
  defp inline_attachment?(_attachment), do: false

  defp consume_reply_attachments(socket) do
    if Enum.any?(socket.assigns.uploads.reply_attachment.entries, &(not &1.done?)) do
      {:error, :upload_in_progress}
    else
      socket
      |> consume_uploaded_entries(:reply_attachment, fn %{path: path}, entry ->
        case File.read(path) do
          {:ok, body} ->
            {:ok,
             {:ok,
              %{
                filename: entry.client_name,
                content_type: entry.client_type || "application/octet-stream",
                body: body
              }}}

          {:error, reason} ->
            {:ok, {:error, reason}}
        end
      end)
      |> case do
        results ->
          case Enum.find(results, &match?({:error, _reason}, &1)) do
            nil -> {:ok, Enum.map(results, fn {:ok, attachment} -> attachment end)}
            {:error, reason} -> {:error, reason}
          end
      end
    end
  end

  defp validate_reply_composer(params, upload) do
    entries = upload.entries

    cond do
      params |> composer_body() |> String.trim() == "" ->
        {:error, :body_required}

      Enum.any?(entries, &(upload_errors(upload, &1) != [])) ->
        {:error, :attachment_invalid}

      Enum.sum(Enum.map(entries, &(&1.client_size || 0))) > @max_total_attachment_size ->
        {:error, :attachments_too_large}

      Enum.any?(entries, &(not &1.done?)) ->
        {:error, :upload_in_progress}

      true ->
        :ok
    end
  end

  defp composer_body(%{"body" => body}) when is_binary(body), do: body
  defp composer_body(_params), do: ""

  defp attachment_upload_error(:too_large), do: gettext("The attachment is too large.")
  defp attachment_upload_error(:too_many_files), do: gettext("Too many attachments selected.")
  defp attachment_upload_error(_error), do: gettext("The attachment could not be uploaded.")

  defp format_datetime(nil), do: ""
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%b %-d, %Y at %H:%M")

  defp relative_time(datetime) do
    seconds = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      seconds < 60 -> gettext("now")
      seconds < 3_600 -> gettext("%{minutes}m", minutes: div(seconds, 60))
      seconds < 86_400 -> gettext("%{hours}h", hours: div(seconds, 3_600))
      true -> gettext("%{days}d", days: div(seconds, 86_400))
    end
  end

  defp status_message("resolved"), do: gettext("Conversation resolved.")
  defp status_message("open"), do: gettext("Conversation reopened.")
  defp status_message("waiting"), do: gettext("Conversation marked waiting.")
  defp status_message(_status), do: gettext("Conversation updated.")

  defp primary_action_label("resolved"), do: gettext("Reopen")
  defp primary_action_label(_status), do: gettext("Resolve")
  defp primary_action_status("resolved"), do: "open"
  defp primary_action_status(_status), do: "resolved"
  defp primary_action_icon("resolved"), do: "reload"
  defp primary_action_icon(_status), do: "check"
end
