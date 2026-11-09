defmodule Tuist.MCP.WebMCPTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.MCP.Server
  alias Tuist.MCP.WebMCP

  @pages ~w(overview builds tests module-cache bundles previews project-settings connect projects runners webhooks sandboxes account-tokens organization ai-subscriptions pulse)
  @build_systems ~w(xcode gradle bazel cargo mix once)

  setup do
    stub(Environment, :tuist_hosted?, fn -> true end)
    stub(Environment, :codebase_search_enabled?, fn -> true end)
    :ok
  end

  test "names pages from their dashboard paths" do
    project = %{build_system: :xcode}
    organization = %{organization_id: 1}
    user = %{organization_id: nil}

    assert WebMCP.dashboard_page("/acme/app", organization, project) == "overview"
    assert WebMCP.dashboard_page("/acme/app/tests/test-runs/1", organization, project) == "tests"
    assert WebMCP.dashboard_page("/acme/app/once/test-runs/1", organization, project) == "tests"
    assert WebMCP.dashboard_page("/acme/app/once/runs/1", organization, project) == "builds"
    assert WebMCP.dashboard_page("/acme/app/gradle-cache", organization, project) == "builds"
    assert WebMCP.dashboard_page("/acme/app/settings/automations", organization, project) == "project-settings"
    # An account page whose name matches a project page is the account's.
    assert WebMCP.dashboard_page("/acme/settings/tokens/1", user, nil) == "account-tokens"
    assert WebMCP.dashboard_page("/acme/settings", organization, nil) == "organization"
    assert WebMCP.dashboard_page("/acme/settings", user, nil) == nil
    assert WebMCP.dashboard_page("/acme/settings/ai", user, nil) == "ai-subscriptions"
    assert WebMCP.dashboard_page("/acme/settings/ai", organization, nil) == nil
    assert WebMCP.dashboard_page("/acme", user, nil) == "projects"
    assert WebMCP.dashboard_page("/acme/cache", organization, nil) == nil
  end

  test "all Pulse pages including issue and event detail offer the same four read tools" do
    organization = %{organization_id: 1}
    pulse_tools = ~w(query_pulse get_pulse_analytics get_pulse_error_issue get_pulse_error_event)

    for path <- ~w(metrics logs traces errors errors/issues/issue errors/issues/issue/events/event) do
      assert WebMCP.dashboard_page("/acme/~/pulse/#{path}", organization, nil) == "pulse"
    end

    assert pulse_tools -- Map.keys(WebMCP.account_server("pulse", nil).tools) == []
    assert Map.keys(WebMCP.public_server().tools) -- pulse_tools == Map.keys(WebMCP.public_server().tools)

    for page <- @pages -- ["pulse"] do
      assert Enum.all?(pulse_tools, &(not Map.has_key?(WebMCP.account_server(page, nil).tools, &1)))
    end
  end

  test "the AI subscriptions page offers only the read-only list, and no other page does" do
    assert "list_ai_subscriptions" in Map.keys(WebMCP.account_server("ai-subscriptions", nil).tools)

    write_tools =
      ~w(connect_claude_subscription start_chatgpt_subscription_login poll_chatgpt_subscription_login cancel_chatgpt_subscription_login disconnect_ai_subscription)

    for page <- @pages, build_system <- [nil | @build_systems] do
      names = Map.keys(WebMCP.account_server(page, build_system).tools)
      assert names -- write_tools == names
      if page != "ai-subscriptions", do: refute("list_ai_subscriptions" in names)
    end
  end

  test "every read-only tool is offered on some page, and no page offers more than 40 tools" do
    page_tools =
      for page <- @pages, build_system <- @build_systems do
        server = WebMCP.account_server(page, build_system)
        assert map_size(server.tools) <= 40, "#{page} (#{build_system}) offers #{map_size(server.tools)} tools"
        assert Enum.all?(Map.values(server.tools), & &1.annotations().readOnlyHint)
        Map.keys(server.tools)
      end

    read_only = for {name, module} <- Server.server().tools, module.annotations().readOnlyHint, do: name

    # Notification rules span every account the user belongs to, so no account page offers them.
    account_spanning = ~w(list_notification_events list_notification_condition_options list_notification_rules)
    # Amp workspace connections and Claude environments need account `:update`
    # even to list, so browser agents never get them.
    admin_only = ~w(list_amp_workspace_connections list_claude_environments)
    not_offered = account_spanning ++ admin_only

    assert read_only -- (not_offered ++ List.flatten(page_tools)) == []
    assert not_offered -- List.flatten(page_tools) == not_offered
  end
end
