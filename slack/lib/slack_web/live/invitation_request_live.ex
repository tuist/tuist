defmodule SlackWeb.InvitationRequestLive do
  @moduledoc """
  Public LiveView where visitors can request an invitation to the
  Tuist Slack workspace. We ask for an email and a short note about
  what brings them to Tuist, then send a confirmation email so we
  know the address is valid before an admin reviews it.
  """
  use SlackWeb, :live_view
  use Noora

  alias Phoenix.HTML.FormField
  alias Slack.Captcha
  alias Slack.Invitations
  alias Slack.Invitations.Invitation

  @impl true
  def mount(_params, _session, socket) do
    remote_ip = connected?(socket) && peer_ip(socket)

    {:ok,
     socket
     |> assign(:page_title, "Join our Slack")
     |> assign(:submitted?, false)
     |> assign(:captcha_error, nil)
     |> assign(:captcha_site_key, Captcha.site_key())
     |> assign(:captcha_enabled?, Captcha.enabled?())
     |> assign(:remote_ip, remote_ip)
     |> assign_new_form()}
  end

  @impl true
  def handle_event("validate", %{"invitation" => params}, socket) do
    form =
      %Invitation{}
      |> Invitations.change_invitation(params)
      |> Map.put(:action, :validate)
      |> to_form(as: "invitation")

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("submit", params, socket) do
    invitation_params = Map.get(params, "invitation", %{})
    captcha_token = Map.get(params, "cf-turnstile-response")

    case Captcha.verify(captcha_token, socket.assigns.remote_ip) do
      :ok ->
        submit_invitation(socket, invitation_params)

      {:error, reason} ->
        {:noreply, assign(socket, captcha_error: captcha_error_message(reason))}
    end
  end

  defp submit_invitation(socket, params) do
    build_confirm_url = fn token -> url(socket, ~p"/invitations/confirm/#{token}") end

    case Invitations.request_invitation(params, build_confirm_url) do
      {:ok, _invitation} ->
        {:noreply,
         socket
         |> assign(:submitted?, true)
         |> assign(:captcha_error, nil)
         |> assign_new_form()}

      {:error, changeset} ->
        form =
          changeset
          |> Map.put(:action, :insert)
          |> to_form(as: "invitation")

        {:noreply, assign(socket, form: form, captcha_error: nil)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="invitation-request">
      <div data-part="content">
        <div data-part="logos">
          <img src={~p"/images/tuist_logo_32x32@2x.png"} alt="Tuist" data-part="logo" />
          <span data-part="logo-separator" aria-hidden="true">+</span>
          <img src={~p"/images/slack_logo.svg"} alt="Slack" data-part="logo" />
        </div>

        <header data-part="header">
          <h1 data-part="title">Join the Tuist Slack</h1>
          <p data-part="subtitle">
            Tell us a little about what brings you here and we'll send a confirmation email.
          </p>
        </header>

        <.alert
          :if={@submitted?}
          id="invitation-submitted-alert"
          type="secondary"
          status="success"
          size="small"
          title="Check your inbox to confirm your email address."
        />

        <.form
          :let={f}
          for={@form}
          id="invitation-form"
          phx-change="validate"
          phx-submit="submit"
          data-part="form"
        >
          <.text_input
            field={f[:email]}
            id="invitation-email"
            label="Email address"
            type="email"
            placeholder="you@example.com"
            show_prefix={false}
            error={field_error(f[:email])}
            required
          />
          <.text_area
            field={f[:reason]}
            id="invitation-reason"
            label="What brought you to Tuist?"
            placeholder="A few sentences about your project or what you're hoping to get out of the community."
            rows={5}
            error={field_error(f[:reason])}
            required
          />

          <div data-part="code-of-conduct">
            <h2 data-part="code-of-conduct-title">Code of conduct</h2>
            <ul data-part="code-of-conduct-list">
              <li>
                <strong>Be kind and respectful.</strong> No harassment, discrimination, or personal attacks.
              </li>
              <li>
                <strong>Keep it constructive.</strong>
                Share what you're building, ask good questions, and help others when you can.
              </li>
              <li>
                <strong>Respect privacy.</strong>
                Don't share private conversations, credentials, or personal info that isn't yours to share.
              </li>
            </ul>
          </div>

          <div data-part="code-of-conduct-consent">
            <label data-part="code-of-conduct-accept">
              <input
                type="checkbox"
                name={f[:code_of_conduct_accepted].name}
                id="invitation-code-of-conduct"
                value="true"
                checked={f[:code_of_conduct_accepted].value in [true, "true"]}
              />
              <span>I agree to follow the Code of Conduct</span>
            </label>
            <span
              :for={error <- f[:code_of_conduct_accepted].errors}
              data-part="code-of-conduct-error"
            >
              {translate_error(error)}
            </span>
          </div>

          <div
            :if={@captcha_enabled?}
            id="invitation-captcha"
            phx-update="ignore"
            class="cf-turnstile"
            data-sitekey={@captcha_site_key}
          >
          </div>
          <span :if={@captcha_error} data-part="captcha-error">{@captcha_error}</span>

          <.button type="submit" variant="primary" size="large" label="Request invitation" />
        </.form>
      </div>
    </section>
    """
  end

  defp assign_new_form(socket) do
    form =
      %Invitation{}
      |> Invitations.change_invitation(%{})
      |> to_form(as: "invitation")

    assign(socket, :form, form)
  end

  defp peer_ip(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
      %{address: address} -> address |> :inet.ntoa() |> to_string()
      _ -> nil
    end
  end

  defp captcha_error_message(:missing_token), do: "Please complete the challenge before submitting."

  defp captcha_error_message({:captcha_failed, _}), do: "The challenge did not pass. Please try again."

  defp captcha_error_message({:unexpected_response, _}),
    do: "We couldn't verify the challenge. Please try again in a moment."

  defp captcha_error_message({:request_failed, _}),
    do: "We couldn't verify the challenge. Please try again in a moment."

  defp field_error(%FormField{errors: []}), do: nil
  defp field_error(%FormField{errors: [error | _]}), do: translate_error(error)

  defp translate_error({message, opts}) do
    Regex.replace(~r/%\{(\w+)\}/, message, fn _, key ->
      opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
    end)
  end
end
