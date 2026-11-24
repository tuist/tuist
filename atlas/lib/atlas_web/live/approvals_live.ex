defmodule AtlasWeb.ApprovalsLive do
  @moduledoc """
  The signed-in person's own pending approvals: gated MCP calls, such as a
  cluster elevation, showing their exact arguments. Any signed-in person can
  open this page, but only the requesting person can decide their requests.
  """
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.Components.EmptyCardSection
  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Audit
  alias Atlas.MCP

  # Legacy Gmail approvals remain stored for audit history, but are no longer actionable.
  @tool_approval_scope [except_server_names: ["gmail"]]

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("My approvals"))}
  end

  # A deep link shows only its own request, so an agent can hand the owner the
  # exact one it is waiting on.
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:approval_id, params["id"])
     |> load_tool_approvals()}
  end

  def handle_event("decide_tool_approval", %{"id" => id, "decision" => decision}, socket)
      when decision in ["approved", "rejected"] do
    user = socket.assigns.current_user

    result =
      Audit.with_context(%{actor: user, interface: "dashboard"}, fn ->
        MCP.decide_tool_approval(user, id, decision, @tool_approval_scope)
      end)

    socket =
      case result do
        {:ok, %{status: "approved"}} ->
          put_flash(socket, :info, gettext("Approved. The agent can now repeat the call once."))

        {:ok, _approval} ->
          put_flash(socket, :info, gettext("Request rejected."))

        {:error, :not_found} ->
          put_flash(socket, :error, gettext("This request is no longer pending."))
      end

    {:noreply, load_tool_approvals(socket)}
  end

  defp load_tool_approvals(socket) do
    approvals = MCP.list_pending_tool_approvals(socket.assigns.current_user, @tool_approval_scope)

    approvals =
      if id = socket.assigns.approval_id,
        do: Enum.filter(approvals, &(&1.id == id)),
        else: approvals

    assign(socket, :tool_approvals, approvals)
  end

  def render(assigns) do
    ~H"""
    <section id="approvals" data-part="account-settings-page">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("My approvals")}</h1>
          <p data-part="description">
            {gettext(
              "Requests from agents to act as you, such as elevating a thread's cluster access. Only you can see and decide them, and each approval covers one action."
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
        :if={@approval_id && @tool_approvals == []}
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
        :if={!@approval_id || @tool_approvals != []}
        id="approvals-pending"
        title={gettext("Pending")}
        icon="circle_check"
      >
        <.empty_card_section
          :if={@tool_approvals == []}
          id="approvals-empty"
          title={gettext("Nothing is waiting for your approval.")}
        >
          <:image>
            <img src="/images/empty_table_light.png" data-theme="light" />
            <img src="/images/empty_table_dark.png" data-theme="dark" />
          </:image>
        </.empty_card_section>
        <div :if={@tool_approvals != []} id="tool-approval-requests" data-part="settings-sections">
          <.card_section
            :for={approval <- @tool_approvals}
            id={"tool-approval-#{approval.id}"}
            data-part="settings-section"
          >
            <div data-part="header">
              <span data-part="title">
                <span data-part="icon"><.icon name="lock" /></span>
                <span id={"tool-approval-tool-#{approval.id}"}>
                  {approval.server_name}/{approval.tool_name}
                </span>
              </span>
              <span data-part="subtitle">
                {gettext(
                  "An agent asked to run this call as you. Approving lets the identical call run once. Requested %{requested}, expires %{expires}.",
                  requested: Calendar.strftime(approval.inserted_at, "%H:%M UTC"),
                  expires: Calendar.strftime(approval.expires_at, "%H:%M UTC")
                )}
              </span>
            </div>
            <div data-part="content">
              <pre id={"tool-approval-arguments-#{approval.id}"} data-part="arguments">{Jason.encode!(approval.arguments, pretty: true)}</pre>
              <div data-part="actions">
                <.button
                  id={"tool-approval-reject-#{approval.id}"}
                  label={gettext("Reject")}
                  variant="secondary"
                  size="medium"
                  phx-click="decide_tool_approval"
                  phx-value-id={approval.id}
                  phx-value-decision="rejected"
                />
                <.button
                  id={"tool-approval-approve-#{approval.id}"}
                  label={gettext("Approve")}
                  variant="primary"
                  size="medium"
                  phx-click="decide_tool_approval"
                  phx-value-id={approval.id}
                  phx-value-decision="approved"
                />
              </div>
            </div>
          </.card_section>
        </div>
      </.card>
    </section>
    """
  end
end
