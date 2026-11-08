defmodule AtlasWeb.ConnectionsLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Audit
  alias Atlas.Connections
  alias Atlas.Connections.Gmail

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Connections"))
     |> stream_configure(:connections, dom_id: &"connection-#{&1.provider}")
     |> assign(:send_edit, nil)
     |> load_connections()
     |> load_gmail_sends()}
  end

  def handle_event("edit_gmail_send", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.gmail_sends, &((&1.approval.id == id and &1.draft) && &1.draft.editable)) do
      nil ->
        {:noreply, socket}

      %{draft: draft} ->
        params = %{"to" => draft.to, "cc" => draft.cc, "subject" => draft.subject, "body" => draft.body}
        {:noreply, assign(socket, :send_edit, %{id: id, params: params})}
    end
  end

  def handle_event("cancel_gmail_send_edit", _params, socket), do: {:noreply, assign(socket, :send_edit, nil)}

  # The edit is written to Gmail first, and the approval then pins the content
  # Gmail holds, which is exactly what the owner submitted.
  def handle_event("save_gmail_send", %{"approval_id" => id, "draft" => params}, socket) do
    user = socket.assigns.current_user

    attrs = %{
      "to" => addresses(params["to"]),
      "cc" => addresses(params["cc"]),
      "subject" => params["subject"] || "",
      "body" => String.replace(params["body"] || "", "\r\n", "\n")
    }

    result = Audit.with_context(%{actor: user, interface: "dashboard"}, fn -> Gmail.revise_send(user, id, attrs) end)

    case result do
      {:ok, %{status: "approved"}} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Saved to Gmail and approved. The agent can now send this draft once."))
         |> assign(:send_edit, nil)
         |> load_gmail_sends()}

      {:error, {:invalid, message}} ->
        {:noreply, socket |> put_flash(:error, message) |> assign(:send_edit, %{id: id, params: params})}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Could not save this draft to Gmail. Reload and try again."))
         |> assign(:send_edit, %{id: id, params: params})}
    end
  end

  # Approving runs only here, in the owner's browser session, after the draft
  # is re-read from Gmail and still matches the request.
  def handle_event("decide_gmail_send", %{"id" => id, "decision" => decision}, socket)
      when decision in ["approved", "rejected"] do
    user = socket.assigns.current_user
    result = Audit.with_context(%{actor: user, interface: "dashboard"}, fn -> Gmail.decide_send(user, id, decision) end)

    socket =
      case result do
        {:ok, %{status: "approved"}} ->
          put_flash(socket, :info, gettext("Approved. The agent can now send this draft once."))

        {:ok, _approval} ->
          put_flash(socket, :info, gettext("Send request rejected."))

        {:error, {:changed, _draft}} ->
          put_flash(socket, :error, gettext("The draft changed since this request, so it was not approved."))

        {:error, _reason} ->
          put_flash(socket, :error, gettext("This request could not be approved. Reload and try again."))
      end

    {:noreply, load_gmail_sends(socket)}
  end

  def handle_event("disconnect", %{"provider" => provider}, socket) do
    result =
      Audit.with_context(%{actor: socket.assigns.current_user, interface: "dashboard"}, fn ->
        Connections.disconnect(socket.assigns.current_user, provider)
      end)

    case result do
      {:ok, :ok} ->
        {:noreply, socket |> put_flash(:info, gettext("Account disconnected from Atlas.")) |> load_connections()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not disconnect your account. Please try again."))}
    end
  end

  defp addresses(value) when is_binary(value),
    do: value |> String.split([",", ";", "\n"], trim: true) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  defp addresses(_value), do: []

  defp load_connections(socket) do
    stream(socket, :connections, Connections.list(socket.assigns.current_user), reset: true)
  end

  # Drafts are read from Gmail for display and never stored in Atlas.
  defp load_gmail_sends(socket) do
    user = socket.assigns.current_user

    sends =
      if connected?(socket),
        do: Audit.with_context(%{actor: user, interface: "dashboard"}, fn -> Gmail.pending_sends(user) end),
        else: []

    assign(socket, :gmail_sends, sends)
  end

  def render(assigns) do
    ~H"""
    <section id="connections" data-part="account-settings-page">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("Connections")}</h1>
          <p data-part="description">
            {gettext(
              "Connect your own accounts so Atlas tools can act with your access. These are separate from your Atlas sign-in."
            )}
          </p>
        </div>
      </div>
      <div :if={@gmail_sends != []} id="gmail-send-requests" data-part="settings-sections">
        <.card_section
          :for={send <- @gmail_sends}
          id={"gmail-approval-#{send.approval.id}"}
          data-part="settings-section"
        >
          <div data-part="header">
            <span data-part="title">
              <span data-part="icon"><.icon name="brand_google" /></span>
              {gettext("Send Gmail draft?")}
            </span>
            <span data-part="subtitle">
              {gettext(
                "An agent asked to send this draft from your mailbox. Approving lets this exact draft be sent once. Requested %{requested}, expires %{expires}.",
                requested: Calendar.strftime(send.approval.inserted_at, "%H:%M UTC"),
                expires: Calendar.strftime(send.approval.expires_at, "%H:%M UTC")
              )}
            </span>
          </div>
          <div data-part="content">
            <.alert
              :if={send.status == :changed}
              id={"gmail-approval-changed-#{send.approval.id}"}
              status="warning"
              type="secondary"
              size="small"
              title={
                if(send.draft && send.draft.editable,
                  do:
                    gettext(
                      "The draft changed after this request. Reject it, or edit it here to approve what you see."
                    ),
                  else:
                    gettext(
                      "The draft changed after this request. Reject it; the agent has to ask again."
                    )
                )
              }
            />
            <.alert
              :if={send.status == :unavailable}
              id={"gmail-approval-unavailable-#{send.approval.id}"}
              status="error"
              type="secondary"
              size="small"
              title={gettext("Atlas could not read this draft from Gmail.")}
            />
            <.form
              :if={editing?(@send_edit, send)}
              for={%{}}
              as={:draft}
              id={"gmail-approval-form-#{send.approval.id}"}
              data-part="draft"
              phx-submit="save_gmail_send"
            >
              <input type="hidden" name="approval_id" value={send.approval.id} />
              <.text_input
                id={"gmail-approval-edit-to-#{send.approval.id}"}
                type="basic"
                name="draft[to]"
                value={@send_edit.params["to"]}
                label={gettext("To")}
                hint={gettext("Email addresses separated by commas.")}
                show_suffix={false}
              />
              <.text_input
                id={"gmail-approval-edit-cc-#{send.approval.id}"}
                type="basic"
                name="draft[cc]"
                value={@send_edit.params["cc"]}
                label={gettext("Cc")}
                show_suffix={false}
              />
              <.text_input
                id={"gmail-approval-edit-subject-#{send.approval.id}"}
                type="basic"
                name="draft[subject]"
                value={@send_edit.params["subject"]}
                label={gettext("Subject")}
                show_suffix={false}
              />
              <.text_area
                id={"gmail-approval-edit-body-#{send.approval.id}"}
                name="draft[body]"
                value={@send_edit.params["body"]}
                label={gettext("Message")}
                aria-label={gettext("Message")}
                rows={12}
                max_length={100_000}
                show_character_count={false}
              />
              <div data-part="actions">
                <.button
                  id={"gmail-approval-cancel-#{send.approval.id}"}
                  type="button"
                  label={gettext("Cancel")}
                  variant="secondary"
                  size="medium"
                  phx-click="cancel_gmail_send_edit"
                />
                <.button
                  id={"gmail-approval-save-#{send.approval.id}"}
                  type="submit"
                  label={gettext("Save and approve send")}
                  variant="primary"
                  size="medium"
                />
              </div>
            </.form>
            <dl :if={send.draft && !editing?(@send_edit, send)} data-part="draft">
              <div data-part="field">
                <dt>{gettext("To")}</dt>
                <dd id={"gmail-approval-to-#{send.approval.id}"}>{send.draft.to}</dd>
              </div>
              <div :if={send.draft.cc != ""} data-part="field">
                <dt>{gettext("Cc")}</dt>
                <dd>{send.draft.cc}</dd>
              </div>
              <div :if={send.draft.bcc != ""} data-part="field">
                <dt>{gettext("Bcc")}</dt>
                <dd>{send.draft.bcc}</dd>
              </div>
              <div data-part="field">
                <dt>{gettext("Subject")}</dt>
                <dd id={"gmail-approval-subject-#{send.approval.id}"}>{send.draft.subject}</dd>
              </div>
              <div :if={send.draft.attachments != []} data-part="field">
                <dt>{gettext("Attachments")}</dt>
                <dd>{Enum.map_join(send.draft.attachments, ", ", & &1["filename"])}</dd>
              </div>
              <div data-part="field">
                <dt>{gettext("Message")}</dt>
                <dd>
                  <pre id={"gmail-approval-body-#{send.approval.id}"} data-part="draft-body">{send.draft.body}</pre>
                </dd>
              </div>
            </dl>
            <div :if={!editing?(@send_edit, send)} data-part="actions">
              <.button
                id={"gmail-approval-reject-#{send.approval.id}"}
                label={gettext("Reject")}
                variant="secondary"
                size="medium"
                phx-click="decide_gmail_send"
                phx-value-id={send.approval.id}
                phx-value-decision="rejected"
              />
              <.button
                :if={send.draft && send.draft.editable}
                id={"gmail-approval-edit-#{send.approval.id}"}
                label={gettext("Edit")}
                variant="secondary"
                size="medium"
                phx-click="edit_gmail_send"
                phx-value-id={send.approval.id}
              />
              <.button
                :if={send.status == :ready}
                id={"gmail-approval-approve-#{send.approval.id}"}
                label={gettext("Approve send")}
                variant="primary"
                size="medium"
                phx-click="decide_gmail_send"
                phx-value-id={send.approval.id}
                phx-value-decision="approved"
              />
            </div>
          </div>
        </.card_section>
      </div>
      <div id="personal-connections" data-part="settings-sections" phx-update="stream">
        <.card_section
          :for={{id, entry} <- @streams.connections}
          id={id}
          data-part="settings-section"
        >
          <div data-part="header">
            <span data-part="title">
              <span data-part="icon"><.icon name={"brand_#{entry.provider}"} /></span>
              {entry.name}
            </span>
            <span data-part="subtitle">{description(entry.provider)}</span>
          </div>
          <div data-part="content">
            <div data-part="connection-row">
              <span id={"connection-account-#{entry.provider}"} data-part="account">
                {entry.account_name || gettext("Account")}
              </span>
              <.status_badge
                id={"connection-status-#{entry.provider}"}
                type="dot"
                status={status_color(entry.status)}
                label={status_label(entry.status)}
              />
            </div>
            <div
              :if={entry.provider == "google" && entry.status != "not_connected"}
              id="connection-gmail"
              data-part="connection-row"
            >
              <span data-part="account">{gettext("Gmail")}</span>
              <.status_badge
                id="connection-gmail-status"
                type="dot"
                status={if(gmail?(entry), do: "success", else: "disabled")}
                label={
                  if(gmail?(entry), do: gettext("Read access granted"), else: gettext("Not granted"))
                }
              />
            </div>
            <div
              :if={entry.provider == "google" && entry.status != "not_connected"}
              id="connection-gmail-drafts"
              data-part="connection-row"
            >
              <span data-part="account">{gettext("Gmail drafts")}</span>
              <.status_badge
                id="connection-gmail-drafts-status"
                type="dot"
                status={if(gmail_drafts?(entry), do: "success", else: "disabled")}
                label={
                  if(gmail_drafts?(entry),
                    do: gettext("Drafts access granted"),
                    else: gettext("Not granted")
                  )
                }
              />
            </div>
            <.alert
              :if={!entry.configured}
              id={"connection-unconfigured-#{entry.provider}"}
              status="information"
              type="secondary"
              size="small"
              title={gettext("An administrator needs to configure this connection.")}
            />
            <div :if={entry.configured} data-part="actions">
              <.button
                :if={entry.status != "not_connected"}
                id={"connection-disconnect-#{entry.provider}"}
                label={gettext("Disconnect")}
                variant="destructive"
                size="medium"
                phx-click="disconnect"
                phx-value-provider={entry.provider}
                data-confirm={gettext("Remove this account's stored credentials from Atlas?")}
              />
              <.button
                :if={entry.provider == "google" && entry.status != "not_connected" && !gmail?(entry)}
                id="connection-gmail-consent"
                href={google_authorize_path(entry, "read")}
                label={gettext("Allow Gmail access")}
                variant="secondary"
                size="medium"
              />
              <.button
                :if={
                  entry.provider == "google" && entry.status != "not_connected" &&
                    !gmail_drafts?(entry)
                }
                id="connection-gmail-drafts-consent"
                href={google_authorize_path(entry, "compose")}
                label={gettext("Allow Gmail drafts")}
                variant="secondary"
                size="medium"
              />
              <.button
                id={"connection-connect-#{entry.provider}"}
                href={authorize_path(entry)}
                label={
                  if(entry.status == "not_connected",
                    do: gettext("Connect"),
                    else: gettext("Reconnect")
                  )
                }
                variant={if(entry.status == "connected", do: "secondary", else: "primary")}
                size="medium"
              />
            </div>
          </div>
        </.card_section>
      </div>
      <p data-part="footnote">
        {gettext(
          "Credentials are encrypted and never shown to agents. Your connections are only used for your own requests: other people and shared Pip threads cannot use them. Disconnecting removes stored credentials; revoke app access in your provider settings to invalidate the grant there too. Gmail monitoring starts only after you configure and enable a signal source."
        )}
      </p>
    </section>
    """
  end

  defp editing?(%{id: id}, %{approval: %{id: id}}), do: true
  defp editing?(_edit, _send), do: false

  defp description("github"),
    do: gettext("Lets Atlas list the repositories you can access when you start coding conversations.")

  defp description("slack"),
    do:
      gettext(
        "Search the messages, channels and DMs you can see in Slack from Atlas tools (search_my_slack). This is separate from the Atlas bot."
      )

  defp description("google"),
    do:
      gettext(
        "Drive files and read-only calendar access. Allow Gmail access to search and read your mail from Atlas tools (search_my_gmail, get_my_gmail_message). Allow Gmail drafts to let them prepare drafts (create_my_gmail_draft, update_my_gmail_draft); a draft is only sent after you approve it here."
      )

  defp description(_provider), do: nil

  # Google returns only the scopes requested by the latest consent, so a plain
  # reconnect or a new Gmail consent would silently drop a granted Gmail scope.
  defp authorize_path(%{provider: "google"} = entry), do: google_authorize_path(entry, nil)
  defp authorize_path(entry), do: ~p"/connections/#{entry.provider}/authorize"

  defp google_authorize_path(entry, consent) do
    requested = [consent, gmail?(entry) && "read", gmail_drafts?(entry) && "compose"]
    consents = Enum.filter(["read", "compose"], &(&1 in requested))

    if consents == [],
      do: ~p"/connections/google/authorize",
      else: "/connections/google/authorize?gmail=" <> Enum.join(consents, ",")
  end

  defp gmail?(entry), do: Gmail.scope() in entry.scopes
  defp gmail_drafts?(entry), do: Gmail.compose_scope() in entry.scopes

  defp status_color("connected"), do: "success"
  defp status_color("needs_authorization"), do: "warning"
  defp status_color(_), do: "disabled"

  defp status_label("connected"), do: gettext("Connected")
  defp status_label("needs_authorization"), do: gettext("Reconnect needed")
  defp status_label(_), do: gettext("Not connected")
end
