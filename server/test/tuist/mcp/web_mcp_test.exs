defmodule Tuist.MCP.WebMCPTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.MCP.Server
  alias Tuist.MCP.WebMCP

  @pages ~w(overview builds tests module-cache bundles previews project-settings connect projects runners webhooks sandboxes account-tokens organization ai-subscriptions)
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

    assert read_only -- List.flatten(page_tools) == []
  end
end
