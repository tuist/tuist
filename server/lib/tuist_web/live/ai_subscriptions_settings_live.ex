defmodule TuistWeb.AISubscriptionsSettingsLive do
  @moduledoc """
  Personal settings page where a user connects their Claude and ChatGPT
  subscriptions for threads, laid out like the Integrations cards. Only the
  user's own personal account renders it, and only while
  `Tuist.FeatureFlags.ai_enabled?/1` holds for them. Credentials never
  enter socket assigns: the Claude token is passed straight to
  `Tuist.Accounts.AISubscriptions`, and ChatGPT only exposes its user code.
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.Terminal

  alias Tuist.Accounts.AISubscriptions
  alias Tuist.FeatureFlags

  @impl true
  def mount(_params, _session, %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket) do
    if selected_account.user_id != current_user.id or not FeatureFlags.ai_enabled?(current_user) do
      raise TuistWeb.Errors.NotFoundError,
            dgettext("dashboard_account", "The page you are looking for doesn't exist or has been moved.")
    end

    {:ok,
     socket
     |> assign(:head_title, "#{dgettext("dashboard", "AI")} · #{selected_account.name} · Tuist")
     |> assign(:claude_form, empty_claude_form())
     |> assign(:claude_error, nil)
     |> assign(:chatgpt_login, nil)
     |> assign(:chatgpt_starting?, false)
     |> assign(:chatgpt_error, nil)
     |> assign(:disconnect_provider, nil)
     |> assign(:chatgpt_modal_open?, false)
     |> assign_subscriptions()
     |> attach_hook(:ai_flag, :handle_event, &require_ai_flag/3)}
  end

  # The flag can be turned off while the page is open; stop acting on events then.
  defp require_ai_flag(_event, _params, socket) do
    if FeatureFlags.ai_enabled?(socket.assigns.current_user),
      do: {:cont, socket},
      else: {:halt, push_navigate(socket, to: ~p"/#{socket.assigns.selected_account.name}/settings")}
  end

  @impl true
  def handle_event("open-claude-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(claude_form: empty_claude_form(), claude_error: nil)
     |> push_event("open-modal", %{id: "connect-claude-modal"})}
  end

  def handle_event("close-claude-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(claude_form: empty_claude_form(), claude_error: nil)
     |> push_event("close-modal", %{id: "connect-claude-modal"})}
  end

  def handle_event("save-claude", %{"claude" => %{"token" => token}}, socket) do
    case AISubscriptions.connect_claude(socket.assigns.current_user, token) do
      :ok ->
        {:noreply,
         socket
         |> assign(claude_form: empty_claude_form(), claude_error: nil)
         |> assign_subscriptions()
         |> push_event("close-modal", %{id: "connect-claude-modal"})}

      {:error, :invalid_claude_token} ->
        {:noreply,
         assign(socket,
           claude_form: empty_claude_form(),
           claude_error: dgettext("dashboard_account", "Paste the token printed by claude setup-token.")
         )}

      {:error, _reason} ->
        {:noreply,
         assign(socket,
           claude_form: empty_claude_form(),
           claude_error: dgettext("dashboard_account", "Could not save your Claude token. Please try again.")
         )}
    end
  end

  def handle_event("open-chatgpt-modal", _params, %{assigns: %{chatgpt_starting?: false}} = socket) do
    user = socket.assigns.current_user

    {:noreply,
     socket
     |> cancel_chatgpt_login()
     |> assign(chatgpt_starting?: true, chatgpt_error: nil, chatgpt_modal_open?: true)
     |> start_async(:chatgpt_start, fn -> AISubscriptions.start_chatgpt(user) end)
     |> push_event("open-modal", %{id: "connect-chatgpt-modal"})}
  end

  def handle_event("open-chatgpt-modal", _params, socket), do: {:noreply, socket}

  def handle_event("close-chatgpt-modal", _params, socket) do
    {:noreply,
     socket
     |> cancel_chatgpt_login()
     |> assign(chatgpt_error: nil, chatgpt_modal_open?: false)
     |> push_event("close-modal", %{id: "connect-chatgpt-modal"})}
  end

  def handle_event("confirm-disconnect", %{"provider" => provider}, socket) when provider in ["claude", "chatgpt"] do
    {:noreply,
     socket
     |> assign(:disconnect_provider, String.to_existing_atom(provider))
     |> push_event("open-modal", %{id: "disconnect-subscription-modal"})}
  end

  def handle_event("cancel-disconnect", _params, socket) do
    {:noreply,
     socket
     |> assign(:disconnect_provider, nil)
     |> push_event("close-modal", %{id: "disconnect-subscription-modal"})}
  end

  def handle_event("disconnect", _params, %{assigns: %{disconnect_provider: nil}} = socket), do: {:noreply, socket}

  def handle_event("disconnect", _params, %{assigns: %{disconnect_provider: provider}} = socket) do
    :ok = AISubscriptions.disconnect(socket.assigns.current_user, provider)

    {:noreply,
     socket
     |> assign(:disconnect_provider, nil)
     |> assign_subscriptions()
     |> push_event("close-modal", %{id: "disconnect-subscription-modal"})}
  end

  @impl true
  # Closed before OpenAI answered: drop the sign-in instead of polling it unseen.
  def handle_async(:chatgpt_start, {:ok, {:ok, login}}, %{assigns: %{chatgpt_modal_open?: false}} = socket) do
    AISubscriptions.cancel_chatgpt(socket.assigns.current_user, login.login_id)
    {:noreply, assign(socket, :chatgpt_starting?, false)}
  end

  def handle_async(:chatgpt_start, {:ok, {:ok, login}}, socket) do
    schedule_poll(login)
    {:noreply, assign(socket, chatgpt_starting?: false, chatgpt_login: login)}
  end

  def handle_async(:chatgpt_start, _result, socket) do
    {:noreply,
     assign(socket,
       chatgpt_starting?: false,
       chatgpt_error:
         dgettext(
           "dashboard_account",
           "Could not start the ChatGPT sign-in. Please try again in a few minutes."
         )
     )}
  end

  def handle_async(:chatgpt_poll, _result, %{assigns: %{chatgpt_login: nil}} = socket), do: {:noreply, socket}

  def handle_async(:chatgpt_poll, {:ok, {:ok, :pending}}, socket) do
    schedule_poll(socket.assigns.chatgpt_login)
    {:noreply, socket}
  end

  def handle_async(:chatgpt_poll, {:ok, {:ok, :connected}}, socket) do
    {:noreply,
     socket
     |> assign(chatgpt_login: nil, chatgpt_modal_open?: false)
     |> assign_subscriptions()
     |> push_event("close-modal", %{id: "connect-chatgpt-modal"})}
  end

  def handle_async(:chatgpt_poll, {:exit, {:shutdown, :cancel}}, socket), do: {:noreply, socket}

  def handle_async(:chatgpt_poll, _result, socket) do
    {:noreply,
     assign(socket,
       chatgpt_login: nil,
       chatgpt_error: dgettext("dashboard_account", "The ChatGPT sign-in did not complete. Please try again.")
     )}
  end

  @impl true
  def handle_info({:poll_chatgpt, login_id}, %{assigns: %{chatgpt_login: %{login_id: login_id}}} = socket) do
    user = socket.assigns.current_user
    {:noreply, start_async(socket, :chatgpt_poll, fn -> AISubscriptions.poll_chatgpt(user, login_id) end)}
  end

  def handle_info({:poll_chatgpt, _login_id}, socket), do: {:noreply, socket}

  # Stop polling first, then cancel. A poll that connected in the meantime
  # makes the cancel a no-op, and reloading shows the connection it saved.
  defp cancel_chatgpt_login(%{assigns: %{chatgpt_login: %{login_id: login_id}}} = socket) do
    socket = cancel_async(socket, :chatgpt_poll)
    AISubscriptions.cancel_chatgpt(socket.assigns.current_user, login_id)
    socket |> assign(:chatgpt_login, nil) |> assign_subscriptions()
  end

  defp cancel_chatgpt_login(socket), do: socket

  defp assign_subscriptions(socket) do
    subscriptions = Map.new(AISubscriptions.list(socket.assigns.current_user), &{&1.provider, &1})
    assign(socket, claude: subscriptions.claude, chatgpt: subscriptions.chatgpt)
  end

  defp schedule_poll(login), do: Process.send_after(self(), {:poll_chatgpt, login.login_id}, login.interval * 1000)

  defp empty_claude_form, do: to_form(%{"token" => ""}, as: "claude")
end
