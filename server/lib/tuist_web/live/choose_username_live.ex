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
          |> assign(:submit_pending?, false)
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
              <span
                :if={@submit_pending?}
                data-part="turnstile-pending"
                aria-live="polite"
              >
                {dgettext("dashboard_auth", "Verifying, one moment...")}
              </span>
              <div data-part="actions">
                <.button
                  type="submit"
                  variant="primary"
                  label={dgettext("dashboard_auth", "Continue")}
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
  def handle_event("choose_username", %{"account" => %{"name" => _}} = params, socket) do
    if socket.assigns.turnstile_required? and not socket.assigns.turnstile_ready? do
      # Optimistic-submit gate. Mirrors user_registration_live: park the
      # submit intent, show a verifying message, and let the hook re-fire
      # the form's submit as soon as the token lands.
      {:noreply,
       socket
       |> assign(:submit_pending?, true)
       |> assign(:turnstile_error, nil)
       |> push_event("turnstile:submit-when-ready", %{id: "oauth-signup-turnstile"})}
    else
      handle_choose_username(params, socket)
    end
  end

  def handle_event("turnstile_state_changed", %{"state" => state}, socket) do
    {:noreply, apply_turnstile_state(socket, state)}
  end

  defp handle_choose_username(%{"account" => %{"name" => username}} = params, socket) do
    socket = assign(socket, :submit_pending?, false)

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

  defp apply_turnstile_state(socket, "error") do
    socket
    |> assign(:turnstile_ready?, false)
    |> assign(
      :turnstile_error,
      dgettext("dashboard_auth", "The security check failed. Please reload the page and try again.")
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

        socket =
          socket
          |> assign(:form, to_form(%{"name" => username}, as: "account"))
          |> assign_username_error(errors)

        {:noreply, reset_turnstile(socket)}

      {:error, :account_handle_taken} ->
        socket =
          socket
          |> assign(:form, to_form(%{"name" => username}, as: "account"))
          |> assign(:error, dgettext("dashboard_auth", "This username has already been taken"))

        {:noreply, reset_turnstile(socket)}

      {:error, :email_taken} ->
        {:noreply, redirect(socket, to: ~p"/auth/cancel-pending-signup")}

      {:error, :internal_server_error} ->
        # Non-changeset failure from Accounts.create_user (a runner bootstrap
        # step, for example). Without this clause the case had no arm to match
        # and the LiveView crashed; the form rendered blank and Continue did
        # nothing.
        socket =
          socket
          |> assign(:form, to_form(%{"name" => username}, as: "account"))
          |> assign(:error, dgettext("dashboard_auth", "Something went wrong. Please try again."))

        {:noreply, reset_turnstile(socket)}

      {:error, errors} when is_map(errors) ->
        socket =
          socket
          |> assign(:form, to_form(%{"name" => username}, as: "account"))
          |> assign_username_error(errors)

        {:noreply, reset_turnstile(socket)}
    end
  end

  # Prefer the :name error (that's the only field this form owns) but never
  # leave the form with no message: a changeset that failed on any other field
  # would otherwise render blank and Continue would silently refuse to advance.
  defp assign_username_error(socket, errors) do
    case Map.get(errors, :name) do
      nil ->
        assign(socket, :error, fallback_error(errors))

      name_error ->
        assign(socket, :error, name_error)
    end
  end

  defp fallback_error(errors) when errors == %{} or is_nil(errors) do
    dgettext("dashboard_auth", "Something went wrong. Please try again.")
  end

  defp fallback_error(errors) do
    errors
    |> Enum.map_join(". ", fn {_field, messages} ->
      messages
      |> List.wrap()
      |> Enum.map_join(". ", &String.trim_trailing(&1, "."))
    end)
    |> then(fn combined ->
      if combined == "", do: dgettext("dashboard_auth", "Something went wrong. Please try again."), else: combined <> "."
    end)
  end

  defp reset_turnstile(socket) do
    socket = assign(socket, :submit_pending?, false)

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
