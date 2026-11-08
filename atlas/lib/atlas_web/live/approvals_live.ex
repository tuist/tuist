defmodule AtlasWeb.ApprovalsLive do
  @moduledoc """
  The signed-in person's own pending approvals: requests an agent filed to act
  as them, which only they can decide. Today these are Gmail sends, reviewed
  against the draft as Gmail holds it; drafts are never stored in Atlas.
  """
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.Components.EmptyCardSection
  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Audit
  alias Atlas.Connections.Gmail

  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, gettext("My approvals")) |> assign(:send_edit, nil)}
  end

  # A deep link shows only its own request, so an agent can hand the owner the
  # exact one it is waiting on.
  def handle_params(params, _uri, socket) do
    {:noreply, socket |> assign(:approval_id, params["id"]) |> assign(:send_edit, nil) |> load_gmail_sends()}
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

  defp addresses(value) when is_binary(value),
    do: value |> String.split([",", ";", "\n"], trim: true) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  defp addresses(_value), do: []

  # Drafts are read from Gmail for display and never stored in Atlas.
  defp load_gmail_sends(socket) do
    user = socket.assigns.current_user

    sends =
      if connected?(socket),
        do: Audit.with_context(%{actor: user, interface: "dashboard"}, fn -> Gmail.pending_sends(user) end),
        else: []

    sends =
      if id = socket.assigns.approval_id,
        do: Enum.filter(sends, &(&1.approval.id == id)),
        else: sends

    assign(socket, :gmail_sends, sends)
  end

  def render(assigns) do
    ~H"""
    <section id="approvals" data-part="account-settings-page">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("My approvals")}</h1>
          <p data-part="description">
            {gettext(
              "Requests from agents to act as you, such as sending an email from your mailbox. Only you can see and decide them, and each approval covers one action."
            )}
          </p>
        </div>
        <.button
          :if={@approval_id}
          id="approvals-all"
          navigate={~p"/approvals"}
          label={gettext("All approvals")}
          variant="secondary"
          size="medium"
        />
      </div>
      <%!-- The dashboard layout has no flash area, so decisions report here. --%>
      <.alert
        :if={Phoenix.Flash.get(@flash, :info)}
        id="flash-info"
        type="secondary"
        status="success"
        size="small"
        title={Phoenix.Flash.get(@flash, :info)}
      />
      <.alert
        :if={Phoenix.Flash.get(@flash, :error)}
        id="flash-error"
        type="secondary"
        status="error"
        size="small"
        title={Phoenix.Flash.get(@flash, :error)}
      />
      <.alert
        :if={@approval_id && @gmail_sends == []}
        id="approval-not-pending"
        status="information"
        type="secondary"
        size="small"
        title={
          gettext(
            "This request is no longer waiting for your approval. It was decided, used or has expired."
          )
        }
      />
      <.card
        :if={!@approval_id && @gmail_sends == []}
        id="approvals-empty"
        title={gettext("Pending")}
        icon="circle_check"
      >
        <.empty_card_section title={gettext("Nothing is waiting for your approval.")}>
          <:image>
            <img src="/images/empty_table_light.png" data-theme="light" />
            <img src="/images/empty_table_dark.png" data-theme="dark" />
          </:image>
        </.empty_card_section>
      </.card>
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
    </section>
    """
  end

  defp editing?(%{id: id}, %{approval: %{id: id}}), do: true
  defp editing?(_edit, _send), do: false
end
