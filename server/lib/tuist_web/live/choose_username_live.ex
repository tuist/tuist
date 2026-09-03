defmodule TuistWeb.ChooseUsernameLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.AppAuthComponents

  alias Tuist.Accounts
  alias Tuist.Ecto.Utils
  alias TuistWeb.SignupProtection
  alias TuistWeb.Turnstile

  @impl true
  def mount(_params, session, socket) do
    case session["pending_oauth_signup"] do
      nil ->
        socket = push_navigate(socket, to: ~p"/users/log_in")

        {:ok, socket}

      oauth_data ->
        suggested_username = suggest_username(oauth_data["email"])
        form = to_form(%{"name" => suggested_username}, as: "account")

        socket =
          socket
          |> assign(:form, form)
          |> assign(:oauth_data, oauth_data)
          |> assign(:email, oauth_data["email"])
          |> assign(:error, nil)
          |> assign(:registration_session_token, Map.get(session, "_csrf_token"))
          |> assign(:turnstile_required?, Turnstile.required?())
          |> assign(:turnstile_site_key, Turnstile.site_key())
          |> assign(:turnstile_error, nil)
          |> assign(:turnstile_ready?, false)
          |> assign(:load_turnstile_script?, Turnstile.required?())

        {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="choose-username">
      <div data-part="wrapper">
        <div data-part="frame">
          <div data-part="content">
            <img
              src={~p"/images/tuist_logo_32x32@2x.png"}
              alt={dgettext("dashboard_auth", "Tuist Logo")}
              data-part="logo"
              decoding="async"
            />
            <div data-part="dots">
              <.dots_light />
              <.dots_dark />
            </div>
            <div data-part="header">
              <h1 data-part="title">{dgettext("dashboard_auth", "Choose a username")}</h1>
              <span data-part="subtitle">
                {dgettext("dashboard_auth", "Choose a username for your account")}
              </span>
            </div>
            <.form
              data-part="form"
              for={@form}
              id="choose-username-form"
              phx-submit="choose_username"
            >
              <.text_input
                id="username"
                field={@form[:name]}
                type="basic"
                label={dgettext("dashboard_auth", "Username")}
                hint={dgettext("dashboard_auth", "Username may only contain alphanumeric characters")}
                error={@error}
                show_required
                required
              />
              <div
                :if={@turnstile_required? and is_binary(@turnstile_site_key)}
                id="oauth-signup-turnstile"
                phx-hook="Turnstile"
                phx-update="ignore"
                data-action="oauth_signup"
                data-sitekey={@turnstile_site_key}
              >
                <input data-turnstile-response name="cf-turnstile-response" type="hidden" />
              </div>
              <span :if={@turnstile_error} data-part="turnstile-error">{@turnstile_error}</span>
              <div data-part="actions">
                <.button
                  type="submit"
                  variant="primary"
                  label={dgettext("dashboard_auth", "Continue")}
                  disabled={@turnstile_required? and not @turnstile_ready?}
                />
              </div>
            </.form>
          </div>
        </div>
      </div>
      <div data-part="background">
        <div data-part="top-right-gradient"></div>
        <div data-part="bottom-left-gradient"></div>
        <div data-part="shell"><.shell /></div>
      </div>
      <.terms_and_privacy />
    </div>
    """
  end

  @impl true
  def handle_event("choose_username", %{"account" => %{"name" => username}} = params, socket) do
    case SignupProtection.verify(socket.assigns.registration_session_token, params, "oauth_signup") do
      :ok ->
        choose_username(username, assign(socket, :turnstile_error, nil))

      {:error, :rate_limited} ->
        {:noreply,
         socket
         |> assign(:turnstile_error, dgettext("dashboard_auth", "Too many sign-up attempts. Please try again later."))
         |> reset_turnstile()}

      {:error, :missing_session} ->
        {:noreply,
         socket
         |> assign(
           :turnstile_error,
           dgettext("dashboard_auth", "Your session has expired. Please reload the page and try again.")
         )
         |> reset_turnstile()}

      {:error, :turnstile_failed} ->
        {:noreply,
         socket
         |> assign(:turnstile_error, dgettext("dashboard_auth", "Please complete the security check and try again."))
         |> reset_turnstile()}
    end
  end

  @impl true
  def handle_event("turnstile_state_changed", %{"state" => state}, socket) do
    {:noreply, apply_turnstile_state(socket, state)}
  end

  defp apply_turnstile_state(socket, "ready"),
    do: socket |> assign(:turnstile_ready?, true) |> assign(:turnstile_error, nil)

  defp apply_turnstile_state(socket, "unavailable") do
    socket
    |> assign(:turnstile_ready?, false)
    |> assign(
      :turnstile_error,
      dgettext(
        "dashboard_auth",
        "The security check could not load. Check for a blocker on challenges.cloudflare.com and reload the page."
      )
    )
  end

  defp apply_turnstile_state(socket, _state), do: assign(socket, :turnstile_ready?, false)

  defp choose_username(username, socket) do
    username = String.trim(username)
    oauth_data = socket.assigns.oauth_data

    case Accounts.create_user_from_pending_oauth(oauth_data, username) do
      {:ok, user} ->
        token = generate_signup_completion_token(user.id, oauth_data["oauth_return_url"])
        {:noreply, redirect(socket, to: ~p"/auth/complete-signup?token=#{token}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = Utils.errors_on(changeset)
        error = Map.get(errors, :name)

        socket =
          socket
          |> assign(:form, to_form(%{"name" => username}, as: "account"))
          |> assign(:error, error)

        {:noreply, reset_turnstile(socket)}

      {:error, :account_handle_taken} ->
        socket =
          socket
          |> assign(:form, to_form(%{"name" => username}, as: "account"))
          |> assign(:error, dgettext("dashboard_auth", "This username has already been taken"))

        {:noreply, reset_turnstile(socket)}

      {:error, :email_taken} ->
        {:noreply, redirect(socket, to: ~p"/auth/cancel-pending-signup")}

      {:error, errors} when is_map(errors) ->
        error = Map.get(errors, :name)

        socket =
          socket
          |> assign(:form, to_form(%{"name" => username}, as: "account"))
          |> assign(:error, error)

        {:noreply, reset_turnstile(socket)}
    end
  end

  defp reset_turnstile(socket) do
    if socket.assigns.turnstile_required? do
      socket
      |> assign(:turnstile_ready?, false)
      |> push_event("turnstile:reset", %{id: "oauth-signup-turnstile"})
    else
      socket
    end
  end

  defp suggest_username(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.replace(".", "-")
    |> String.replace("_", "-")
    |> String.replace(~r/[^a-zA-Z0-9-]/, "")
    |> String.downcase()
  end

  defp generate_signup_completion_token(user_id, oauth_return_url) do
    data = %{user_id: user_id, oauth_return_url: oauth_return_url}
    Phoenix.Token.sign(TuistWeb.Endpoint, "signup_completion", data)
  end
end
