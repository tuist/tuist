defmodule AtlasWeb.LLMProviderSettingsLiveTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Atlas.LLMs.ChatGPT
  alias Atlas.LLMs.Connection
  alias Atlas.LLMs.Connections
  alias Atlas.Repo

  test "signed-out visitors are redirected", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/settings/llm-providers")
  end

  test "empty settings use the account layout and a provider dropdown instead of inline credentials", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, ~p"/settings/llm-providers")
    assert has_element?(view, "#account-layout")
    assert has_element?(view, "#account-settings-sidebar")
    assert has_element?(view, "#account-ai-providers-link [data-selected]", "AI accounts")
    assert has_element?(view, "#llm-provider-settings h1", "AI accounts")
    assert has_element?(view, "#add-ai-provider", "Connect account")
    assert has_element?(view, "#providers-empty-state", "No AI accounts connected")
    refute render(view) =~ "AI providers"
    assert has_element?(view, "#account-menu-dashboard-link")
    refute has_element?(view, "#sidebar-commercial")
    assert has_element?(view, "#providers-empty-state")
    refute has_element?(view, "#ai-providers-table")
    refute has_element?(view, "#llm-provider-settings > p[data-part='description']")
    refute has_provider_element?(view, "#claude-token")
    view |> element("#add-ai-provider") |> render_click()
    assert has_provider_element?(view, "#add-provider-modal", "Connect account")
    assert has_provider_element?(view, "#llm-provider-select", "Choose service")
    assert has_provider_element?(view, "#llm-provider-select[data-on-value-change='select_provider']")
    assert has_provider_element?(view, "#llm-provider-select option[value='claude']")
    assert has_provider_element?(view, "#llm-provider-select option[value='chatgpt']")
    refute has_provider_element?(view, "#back-to-provider-picker")
  end

  test "the provider dropdown stays visible while switching setup forms and resets on reopening", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, ~p"/settings/llm-providers")
    choose_provider(view, "claude")
    assert has_provider_element?(view, "#claude-provider-form")
    assert has_provider_element?(view, "#llm-provider-select option[value='claude'][selected]")

    render_hook(view, "select_provider", %{"value" => ["chatgpt"]})
    assert has_provider_element?(view, "#llm-provider-select option[value='chatgpt'][selected]")
    assert has_provider_element?(view, "#chatgpt-provider-setup")
    refute has_provider_element?(view, "#claude-provider-form")
    refute has_provider_element?(view, "#save-claude-provider")

    render_hook(view, "select_provider", %{"value" => ["claude"]})
    assert has_provider_element?(view, "#claude-token[value='']")
    refute has_provider_element?(view, "#chatgpt-provider-setup")
    view |> element("#add-provider-modal [data-part='close-trigger']") |> render_click()
    view |> element("#add-ai-provider") |> render_click()
    assert has_provider_element?(view, "#llm-provider-select")
    refute has_provider_element?(view, "#llm-provider-select option[selected]")
    refute has_provider_element?(view, "#claude-provider-form")
    refute has_provider_element?(view, "#chatgpt-provider-setup")
  end

  test "saved providers are table rows with update and confirmed disconnect actions", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    assert {:ok, _} = Connections.connect_claude(user, claude_token())
    {:ok, view, _html} = live(conn, ~p"/settings/llm-providers")
    refute has_element?(view, "#providers-empty-state")
    assert has_element?(view, "#ai-providers-table #provider-claude")
    refute has_element?(view, "#provider-chatgpt")
    refute has_provider_element?(view, "#claude-token")

    assert has_provider_element?(view, "#update-claude-provider")
    render_click(view, "configure_provider", %{"provider" => "claude"})
    assert has_provider_element?(view, "#claude-token[value='']")
    view |> element("#add-provider-modal [data-part='close-trigger']") |> render_click()
    refute has_provider_element?(view, "#claude-token")

    assert has_provider_element?(view, "#disconnect-claude-provider")
    render_click(view, "request_disconnect", %{"provider" => "claude"})
    assert {:ok, _} = Connections.credentials(user, "claude")
    render_click(view, "disconnect")
    assert has_element?(view, "#providers-empty-state")
    refute has_element?(view, "#ai-providers-table")
    assert {:error, :not_connected} = Connections.credentials(user, "claude")
  end

  test "Claude modal submits a regular CSRF-protected form without retaining credentials", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, ~p"/settings/llm-providers")
    choose_provider(view, "claude")
    assert has_provider_element?(view, "#claude-provider-form[action='/settings/llm-providers/claude'][method='post']")
    assert has_provider_element?(view, "#claude-provider-form input[name='_csrf_token']")
    refute has_provider_element?(view, "#claude-provider-form[phx-submit]")
    token = claude_token()
    saved = post(conn, ~p"/settings/llm-providers/claude", %{claude: %{token: token}})
    assert redirected_to(saved) == ~p"/settings/llm-providers"
    {:ok, updated_view, _html} = live(saved, ~p"/settings/llm-providers")
    assert has_element?(updated_view, "#provider-claude")
    refute has_provider_element?(updated_view, "#claude-token")
    assert has_element?(updated_view, "#flash-info")
    assert {:ok, %{access_token: ^token}} = Connections.credentials(user, "claude")
    render_click(updated_view, "configure_provider", %{"provider" => "claude"})
    assert has_provider_element?(updated_view, "#claude-token[value='']")
  end

  test "ChatGPT setup explains when login is unavailable", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    stub(ChatGPT, :client_id, fn -> {:error, :chatgpt_not_configured} end)
    {:ok, view, _html} = live(conn, ~p"/settings/llm-providers")
    choose_provider(view, "chatgpt")
    assert has_provider_element?(view, "#chatgpt-unavailable")
    assert has_provider_element?(view, "#connect-chatgpt-provider[disabled]")
  end

  test "closing the modal cancels device sign-in and ignores stale polls", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    stub(ChatGPT, :client_id, fn -> {:ok, "atlas-client"} end)
    stub(ChatGPT, :start, fn -> {:ok, device_login()} end)
    {:ok, view, _html} = live(conn, ~p"/settings/llm-providers")
    choose_provider(view, "chatgpt")
    render_click(view, "start_chatgpt")
    render_async(view)
    assert has_provider_element?(view, "#chatgpt-user-code", "USER-CODE")
    assert has_provider_element?(view, "#chatgpt-verification-link[href='https://auth.openai.com/codex/device']")
    connection = Repo.get_by!(Connection, user_id: user.id, provider: "chatgpt")
    login_id = JSON.decode!(connection.pending_login)["id"]
    render_hook(view, "provider_modal_changed", %{"open" => false})
    refute has_provider_element?(view, "#chatgpt-device-login")
    refute has_provider_element?(view, "#chatgpt-provider-setup")
    assert {:error, :not_found} = Connections.poll_chatgpt(user, login_id)
    send(view.pid, {:poll_chatgpt, login_id})
    refute has_provider_element?(view, "#chatgpt-device-login")
    assert {:error, :not_connected} = Connections.credentials(user, "chatgpt")
  end

  test "switching away from ChatGPT cancels its device sign-in", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    stub(ChatGPT, :client_id, fn -> {:ok, "atlas-client"} end)
    stub(ChatGPT, :start, fn -> {:ok, device_login()} end)
    {:ok, view, _html} = live(conn, ~p"/settings/llm-providers")
    choose_provider(view, "chatgpt")
    render_click(view, "start_chatgpt")
    render_async(view)
    assert has_provider_element?(view, "#chatgpt-user-code")

    render_hook(view, "select_provider", %{"value" => ["claude"]})
    assert has_provider_element?(view, "#claude-provider-form")
    refute has_provider_element?(view, "#chatgpt-device-login")
    assert Repo.get_by!(Connection, user_id: user.id, provider: "chatgpt").pending_login == nil
  end

  test "closing during an in-flight device authorization clears the eventual pending login", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    test_pid = self()
    stub(ChatGPT, :client_id, fn -> {:ok, "atlas-client"} end)

    stub(ChatGPT, :start, fn ->
      send(test_pid, {:authorization_started, self()})

      receive do
        :complete_authorization -> {:ok, device_login()}
      end
    end)

    {:ok, view, _html} = live(conn, ~p"/settings/llm-providers")
    choose_provider(view, "chatgpt")
    render_click(view, "start_chatgpt")
    assert_receive {:authorization_started, task_pid}
    render_hook(view, "provider_modal_changed", %{"open" => false})
    send(task_pid, :complete_authorization)
    render_async(view)

    assert Repo.get_by!(Connection, user_id: user.id, provider: "chatgpt").pending_login == nil
    refute has_provider_element?(view, "#chatgpt-device-login")
    choose_provider(view, "chatgpt")
    refute has_provider_element?(view, "#connect-chatgpt-provider[disabled]")
  end

  test "completed ChatGPT authorization populates the table and closes setup", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    stub(ChatGPT, :client_id, fn -> {:ok, "atlas-client"} end)
    stub(ChatGPT, :start, fn -> {:ok, device_login()} end)

    stub(ChatGPT, :poll, fn _login ->
      {:ok,
       %{
         access_token: "private-access-token",
         refresh_token: "private-refresh-token",
         expires_at: DateTime.add(DateTime.utc_now(:second), 3600)
       }}
    end)

    {:ok, view, _html} = live(conn, ~p"/settings/llm-providers")
    choose_provider(view, "chatgpt")
    render_click(view, "start_chatgpt")
    render_async(view)
    connection = Repo.get_by!(Connection, user_id: user.id, provider: "chatgpt")
    login_id = JSON.decode!(connection.pending_login)["id"]
    connection |> Ecto.Changeset.change(next_poll_at: DateTime.add(DateTime.utc_now(:second), -1)) |> Repo.update!()
    send(view.pid, {:poll_chatgpt, login_id})
    render(view)
    render_async(view)

    assert has_element?(view, "#ai-providers-table #provider-chatgpt")
    refute has_element?(view, "#providers-empty-state")
    refute has_provider_element?(view, "#chatgpt-device-login")
    assert has_element?(view, "#flash-info", "ChatGPT connected.")
    refute render(view) =~ "private-access-token"
    refute render(view) =~ "private-refresh-token"
  end

  defp choose_provider(view, provider) do
    view |> element("#add-ai-provider") |> render_click()
    assert has_provider_element?(view, "#llm-provider-select option[value='#{provider}']")
    render_hook(view, "select_provider", %{"value" => [provider]})
  end

  defp has_provider_element?(view, selector, text \\ nil) do
    elements =
      view
      |> render()
      |> String.replace(~r/<\/?template\b[^>]*>/, "")
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(selector)

    Enum.any?(elements) and (is_nil(text) or String.contains?(LazyHTML.text(elements), text))
  end

  defp claude_token, do: "sk-ant-oat01-" <> String.duplicate("a", 64)

  defp device_login do
    %{
      "device_auth_id" => "private-device-id",
      "user_code" => "USER-CODE",
      "client_id" => "atlas-client",
      "interval" => 5,
      "verification_url" => "https://auth.openai.com/codex/device"
    }
  end
end
