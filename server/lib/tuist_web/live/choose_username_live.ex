defmodule TuistWeb.ChooseUsernameLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Accounts

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
              src="/images/tuist_logo_32x32@2x.png"
              alt={dgettext("dashboard_auth", "Tuist Logo")}
              data-part="logo"
            />
            <div data-part="dots">
              <.dots_light />
              <.dots_dark />
            </div>
            <div data-part="header">
              <h1 data-part="title">{dgettext("dashboard_auth", "Choose a username")}</h1>
              <span data-part="subtitle">
                {dgettext("dashboard_auth", "Choose a username for your personal account")}
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
    </div>
    """
  end

  @impl true
  def handle_event("choose_username", %{"account" => %{"name" => username}}, socket) do
    username = String.trim(username)
    oauth_data = socket.assigns.oauth_data

    case Accounts.create_user_from_pending_oauth(oauth_data, username) do
      {:ok, user} ->
        token = generate_signup_completion_token(user.id, oauth_data["oauth_return_url"])
        {:noreply, redirect(socket, to: ~p"/auth/complete-signup?token=#{token}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = Tuist.Ecto.Utils.errors_on(changeset)
        error = Map.get(errors, :name)

        socket =
          socket
          |> assign(:form, to_form(%{"name" => username}, as: "account"))
          |> assign(:error, error)

        {:noreply, socket}

      {:error, :account_handle_taken} ->
        socket =
          socket
          |> assign(:form, to_form(%{"name" => username}, as: "account"))
          |> assign(:error, dgettext("dashboard_auth", "This username has already been taken"))

        {:noreply, socket}

      {:error, errors} when is_map(errors) ->
        error = Map.get(errors, :name)

        socket =
          socket
          |> assign(:form, to_form(%{"name" => username}, as: "account"))
          |> assign(:error, error)

        {:noreply, socket}
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
