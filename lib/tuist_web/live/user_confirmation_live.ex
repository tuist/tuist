defmodule TuistWeb.UserConfirmationLive do
  use TuistWeb, :live_view
  use TuistWeb.Noora

  alias Tuist.Accounts

  def render(assigns) do
    ~H"""
    <%= if FunWithFlags.enabled?(:noora) do %>
      <.noora_confirmation {assigns} />
    <% else %>
      <.legacy_confirmation {assigns} />
    <% end %>
    """
  end

  def noora_confirmation(assigns) do
    ~H"""
    <div id="confirmation">
      <div data-part="wrapper">
        <div data-part="frame">
          <div data-part="content">
            <img src="/images/tuist_logo_32x32@2x.png" alt={gettext("Tuist Logo")} data-part="logo" />
            <div data-part="dots">
              <.dots_light />
              <.dots_dark />
            </div>
            <%= if @success do %>
              <div data-part="header">
                <h1 data-part="title">{gettext("Account confirmed!")}</h1>
                <span data-part="subtitle">
                  {gettext("Your account has been confirmed.")}
                </span>
              </div>
              <.alert
                id="confirmation-success"
                type="secondary"
                status="success"
                size="small"
                title={gettext("Your account has been confirmed. You will be redirected shortly...")}
              />
            <% else %>
              <div data-part="header">
                <h1 data-part="title">{gettext("Confirmation failed")}</h1>
                <span data-part="subtitle">
                  {gettext("Your account could not be confirmed.")}
                </span>
              </div>
              <.alert
                id="confirmation-failure"
                type="secondary"
                status="error"
                size="small"
                title={gettext("User confirmation link is invalid or it has expired.")}
              />
            <% end %>
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

  def legacy_confirmation(%{live_action: :edit} = assigns) do
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
        <.legacy_button type="submit" variant="primary" class="auth-form__primary-action">
          {gettext("Confirm my account")}
        </.legacy_button>
      </.simple_form>

      <.link href={~p"/users/log_in"} class="text--small font--semibold">
        {gettext("Back to log in")}
      </.link>

      <.flash_group flash={@flash} />
    </.stack>
    """
  end

  def handle_params(%{"token" => token}, _session, socket) do
    form = to_form(%{"token" => token}, as: "user")

    if FunWithFlags.enabled?(:noora) do
      case Accounts.confirm_user(token) do
        {:ok, _} ->
          Process.send_after(self(), :redirect, 5000)
          {:noreply, assign(socket, success: true)}

        :error ->
          {:noreply, assign(socket, success: false)}
      end
    else
      {:noreply, assign(socket, form: form, temporary_assigns: [form: nil])}
    end
  end

  def handle_info(:redirect, socket) do
    {:noreply, redirect(socket, to: ~p"/auth/create-project")}
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
