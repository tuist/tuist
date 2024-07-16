defmodule TuistWeb.UserResetPasswordLive do
  use TuistWeb, :live_view

  alias Tuist.Accounts

  def render(assigns) do
    ~H"""
    <.stack class="auth-page" gap="4xl">
      <.auth_header
        title={gettext("Set new password")}
        subtitle={gettext("Your new password must be different to previously used passwords.")}
      >
        <:icon>
          <.featured_icon>
            <.lock_icon />
          </.featured_icon>
        </:icon>
      </.auth_header>

      <.simple_form for={@form} id="reset_password_form" phx-submit="reset_password" class="auth-form">
        <.stack gap="3xl">
          <.input field={@form[:password]} type="password" label={gettext("New password")} required />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label={gettext("Confirm new password")}
            required
          />
          <.stack gap="xl">
            <.button type="submit" variant="primary" class="auth-form__primary-action">
              <%= gettext("Reset password") %>
            </.button>
          </.stack>
        </.stack>
      </.simple_form>

      <.link href={~p"/users/log_in"} class="text--small font--semibold">
        <%= gettext("Back to log in") %>
      </.link>

      <.flash_group flash={@flash} />
    </.stack>
    """
  end

  def mount(params, _session, socket) do
    password = Phoenix.Flash.get(socket.assigns.flash, :password)
    form = to_form(%{"password" => password}, as: "user")

    {
      :ok,
      assign_user_and_token(socket, params)
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
         |> put_flash(:info, gettext("Password reset successfully."))
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
