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
  alias Tuist.Accounts.MCPServers
  alias Tuist.Environment
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
     |> assign(:mcp_form, empty_mcp_form())
     |> assign(:mcp_error, nil)
     |> assign(:mcp_authorizing, nil)
     |> assign(:remove_mcp_server, nil)
     |> assign(:mcp_modal_open?, false)
     |> assign_subscriptions()
     |> assign_mcp_servers()
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

  def handle_event("open-mcp-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(mcp_form: empty_mcp_form(), mcp_error: nil, mcp_modal_open?: true)
     |> push_event("open-modal", %{id: "add-mcp-server-modal"})}
  end

  def handle_event("close-mcp-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(mcp_form: empty_mcp_form(), mcp_error: nil, mcp_modal_open?: false)
     |> push_event("close-modal", %{id: "add-mcp-server-modal"})}
  end

  def handle_event("add-mcp-server", _params, %{assigns: %{mcp_authorizing: id}} = socket) when not is_nil(id),
    do: {:noreply, socket}

  def handle_event("add-mcp-server", %{"mcp_server" => attrs}, socket) do
    case MCPServers.add(socket.assigns.current_user, attrs) do
      {:ok, server} ->
        {:noreply, socket |> assign(:mcp_form, to_form(attrs, as: "mcp_server")) |> authorize_mcp_server(server.id)}

      {:error, reason} ->
        {:noreply, assign(socket, mcp_form: to_form(attrs, as: "mcp_server"), mcp_error: mcp_error_message(reason))}
    end
  end

  def handle_event("connect-mcp-server", %{"id" => id}, %{assigns: %{mcp_authorizing: nil}} = socket) do
    {:noreply, socket |> assign(:mcp_error, nil) |> authorize_mcp_server(id)}
  end

  def handle_event("connect-mcp-server", _params, socket), do: {:noreply, socket}

  def handle_event("confirm-remove-mcp-server", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:remove_mcp_server, Enum.find(socket.assigns.mcp_servers, &(&1.id == id)))
     |> push_event("open-modal", %{id: "remove-mcp-server-modal"})}
  end

  def handle_event("cancel-remove-mcp-server", _params, socket) do
    {:noreply,
     socket
     |> assign(:remove_mcp_server, nil)
     |> push_event("close-modal", %{id: "remove-mcp-server-modal"})}
  end

  def handle_event("remove-mcp-server", _params, %{assigns: %{remove_mcp_server: nil}} = socket), do: {:noreply, socket}

  def handle_event("remove-mcp-server", _params, %{assigns: %{remove_mcp_server: server}} = socket) do
    :ok = MCPServers.remove(socket.assigns.current_user, server.id)

    {:noreply,
     socket
     |> assign(:remove_mcp_server, nil)
     |> assign_mcp_servers()
     |> push_event("close-modal", %{id: "remove-mcp-server-modal"})}
  end

  @impl true
  def handle_async(:mcp_authorize, {:ok, {:ok, authorization_url}}, socket) do
    {:noreply, socket |> assign(:mcp_authorizing, nil) |> redirect(external: authorization_url)}
  end

  def handle_async(:mcp_authorize, result, socket) do
    # Every failure past the URL check reads the same, so the message does not
    # reveal which hosts or ports Tuist can reach.
    reason =
      case result do
        {:ok, {:error, reason}} when reason in [:rate_limited, :not_found] -> reason
        _ -> :sign_in_unavailable
      end

    {:noreply,
     socket
     |> assign(mcp_authorizing: nil, mcp_error: mcp_error_message(reason))
     |> assign_mcp_servers()}
  end

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

  defp empty_mcp_form, do: to_form(%{"name" => "", "url" => ""}, as: "mcp_server")

  defp assign_mcp_servers(socket), do: assign(socket, :mcp_servers, MCPServers.list(socket.assigns.current_user))

  # Discovery and client registration call the server, so they run off the
  # LiveView process; the browser leaves for the authorization server after.
  defp authorize_mcp_server(socket, server_id) do
    user = socket.assigns.current_user
    redirect_uri = Environment.app_url(path: ~p"/integrations/mcp/callback")

    socket
    |> assign(:mcp_authorizing, server_id)
    |> assign_mcp_servers()
    |> start_async(:mcp_authorize, fn -> MCPServers.start_authorization(user, server_id, redirect_uri) end)
  end

  defp mcp_error_message(:invalid_url),
    do: dgettext("dashboard_account", "Enter the server's HTTPS endpoint, for example https://example.com/mcp.")

  defp mcp_error_message(:too_many_servers),
    do: dgettext("dashboard_account", "You can add up to 25 MCP servers. Remove one to add another.")

  defp mcp_error_message(:rate_limited),
    do: dgettext("dashboard_account", "Too many sign-in attempts. Please try again in a few minutes.")

  defp mcp_error_message(:invalid_name), do: dgettext("dashboard_account", "Names can be up to 64 characters long.")

  defp mcp_error_message(_reason),
    do:
      dgettext(
        "dashboard_account",
        "Could not sign in to this server. Check that the URL is right and that the server supports MCP OAuth sign-in with dynamic client registration."
      )
end
