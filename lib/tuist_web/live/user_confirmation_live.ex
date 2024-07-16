defmodule TuistWeb.UserConfirmationLive do
  use TuistWeb, :live_view

  alias Tuist.Accounts

  def render(%{live_action: :edit} = assigns) do
    ~H"""
    <.stack class="auth-page" gap="4xl">
      <.auth_header
        title={gettext("Confirm account")}
        subtitle={gettext("Confirm your account to access Tuist.")}
      >
        <:icon>
          <.featured_icon>
            <.mail_icon />
          </.featured_icon>
        </:icon>
      </.auth_header>

      <.simple_form for={@form} id="confirmation_form" phx-submit="confirm_account" class="auth-form">
        <.input field={@form[:token]} type="hidden" />
        <.button type="submit" variant="primary" class="auth-form__primary-action">
          <%= gettext("Confirm my account") %>
        </.button>
      </.simple_form>

      <.link href={~p"/users/log_in"} class="text--small font--semibold">
        <%= gettext("Back to log in") %>
      </.link>

      <.flash_group flash={@flash} />
    </.stack>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    form = to_form(%{"token" => token}, as: "user")
    {:ok, assign(socket, form: form), temporary_assigns: [form: nil]}
  end

  # Do not log in the user after confirmation to avoid a
  # leaked token giving the user access to the account.
  def handle_event("confirm_account", %{"user" => %{"token" => token}}, socket) do
    case Accounts.confirm_user(token) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "User confirmed successfully.")
         |> redirect(to: ~p"/")}

      :error ->
        # If there is a current user and the account was already confirmed,
        # then odds are that the confirmation link was already visited, either
        # by some automation or by the user themselves, so we redirect without
        # a warning message.
        case socket.assigns do
          %{current_user: %{confirmed_at: confirmed_at}} when not is_nil(confirmed_at) ->
            {:noreply, redirect(socket, to: ~p"/")}

          %{} ->
            {:noreply,
             socket
             |> put_flash(:error, "User confirmation link is invalid or it has expired.")
             |> redirect(to: ~p"/")}
        end
    end
  end
end
