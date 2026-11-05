defmodule TuistWeb.DeviceAuthorizationLive do
  @moduledoc """
  Where a person enters the code their terminal shows to sign it in, in the
  standard device flow (RFC 8628). The page only collects the code; the
  CSRF-protected POST to `TuistWeb.AuthController.confirm_user_code/2`
  approves it, behind the same single sign-on checks as the other device
  sign-in routes.
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.DeviceCodeHTML, only: [device_code_frame: 1]

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       user_code: "",
       email: socket.assigns.current_user.email,
       head_title: dgettext("dashboard_auth", "Sign in to Tuist")
     )}
  end

  def handle_event("user-code-changed", %{"valueAsString" => user_code}, socket) do
    {:noreply, assign(socket, user_code: user_code)}
  end

  def render(assigns) do
    ~H"""
    <.device_code_frame
      title={dgettext("dashboard_auth", "Sign in to the Tuist CLI")}
      subtitle={dgettext("dashboard_auth", "Enter the code shown in your terminal.")}
    >
      <.alert
        type="secondary"
        status="information"
        size="small"
        title={dgettext("dashboard_auth", "Signed in to Tuist as %{email}", email: @email)}
      />
      <.alert
        :if={error = Phoenix.Flash.get(@flash, :error)}
        id="device-code-error"
        type="secondary"
        status="error"
        size="small"
        title={error}
      />
      <.form for={%{}} as={:device} action={~p"/auth/device"} method="post" data-part="form">
        <%!-- The Noora hook owns these inputs; re-rendering them would reset what was typed. --%>
        <div id="user-code-container" phx-update="ignore" data-part="user-code">
          <.digit_input
            id="user-code"
            characters={8}
            type="alphabetic"
            placeholder="•"
            on_change="user-code-changed"
          />
        </div>
        <input type="hidden" name="user_code" value={@user_code} />
        <div data-part="actions">
          <.button
            id="confirm-user-code"
            variant="primary"
            size="large"
            type="submit"
            label={dgettext("dashboard_auth", "Sign in")}
          />
        </div>
      </.form>
      <div data-part="security-note">
        <span data-part="icon"><.lock /></span>
        <span>
          {dgettext(
            "dashboard_auth",
            "Only enter a code from a terminal you are using. Never enter a code someone sent you."
          )}
        </span>
      </div>
    </.device_code_frame>
    """
  end
end
