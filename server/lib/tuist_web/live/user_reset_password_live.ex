defmodule TuistWeb.UserResetPasswordLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Accounts

  def render(assigns) do
    ~H"""
    <.noora_reset_password {assigns} />
    """
  end

  def noora_reset_password(assigns) do
    ~H"""
    <div id="reset-password">
      <div data-part="wrapper">
        <div data-part="frame">
          <div data-part="content">
            <img
              src="/images/tuist_logo_32x32@2x.png"
              alt={dgettext("dashboard_auth", "Tuist Logo")}
              data-part="logo"
            />
            <div data-part="dots">
              <.dots_light />
              <.dots_dark />
            </div>
            <div data-part="header">
              <h1 data-part="title">{dgettext("dashboard_auth", "Change your password")}</h1>
              <span data-part="subtitle">
                {dgettext(
                  "dashboard_auth",
                  "Your new password must be different to previously used passwords."
                )}
              </span>
            </div>
            <.form data-part="form" for={@form} id="reset_password_form" phx-submit="reset_password">
              <.text_input
                field={@form[:password]}
                input_type="password"
                label={dgettext("dashboard_auth", "New password")}
                show_prefix={false}
                show_suffix={false}
                required
              />
              <.text_input
                field={@form[:password_confirmation]}
                input_type="password"
                label={dgettext("dashboard_auth", "Confirm password")}
                show_prefix={false}
                show_suffix={false}
                required
              />
              <.button
                variant="primary"
                size="large"
                label={dgettext("dashboard_auth", "Reset password")}
              />
            </.form>
          </div>
        </div>
      </div>

      <div data-part="background">
        <div data-part="top-right-gradient"></div>
        <div data-part="bottom-left-gradient"></div>
        <div data-part="shell"><.shell /></div>
      </div>
    </div>
    """
  end

  def mount(params, _session, socket) do
    password = Phoenix.Flash.get(socket.assigns.flash, :password)
    form = to_form(%{"password" => password}, as: "user")

    {
      :ok,
      socket
      |> assign_user_and_token(params)
      |> assign(:form, form),
      temporary_assigns: [form: form]
    }
  end

  # Do not log in the user after reset password to avoid a
  # leaked token giving the user access to the account.
  def handle_event("reset_password", %{"user" => user_params}, socket) do
    case Accounts.reset_user_password(socket.assigns.user, user_params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("dashboard_auth", "Password reset successfully."))
         |> redirect(to: ~p"/users/log_in")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :insert))}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_password(socket.assigns.user, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_user_and_token(socket, %{"token" => token}) do
    if user = Accounts.get_user_by_reset_password_token(token) do
      assign(socket, user: user, token: token)
    else
      socket
      |> put_flash(:error, "Reset password link is invalid or it has expired.")
      |> redirect(to: ~p"/users/log_in")
    end
  end

  defp assign_form(socket, %{} = source) do
    assign(socket, :form, to_form(source, as: "user"))
  end
end
