defmodule TuistWeb.Components.LayoutComponentsTest do
  use ExUnit.Case, async: true
  use Mimic

  import Phoenix.LiveViewTest

  alias TuistWeb.LayoutComponents
  alias TuistWeb.Router

  test "loads the Atlas support chat and permits it in the content security policy" do
    html = render_component(&LayoutComponents.head_support_chat_script/1, %{})
    content_security_policy = Router.csp_opts(%{})

    assert html =~ ~s(src="https://atlas.tuist.dev/support/chat.js")
    refute html =~ "plain"

    assert Keyword.fetch!(content_security_policy, :script_src_elem) =~ "https://atlas.tuist.dev"
    assert Keyword.fetch!(content_security_policy, :frame_src) =~ "https://atlas.tuist.dev"
    refute Keyword.fetch!(content_security_policy, :script_src_elem) =~ "plain"
  end

  test "omits the Atlas support chat from embedded blog visualizations" do
    html = render_component(&LayoutComponents.head_support_chat_script/1, %{support_chat_disabled?: true})

    refute html =~ "atlas.tuist.dev"
  end

  test "renders the Faro analytics configuration without external Grafana requests" do
    stub(Tuist.Environment, :analytics_enabled?, fn -> true end)
    stub(Tuist.Environment, :faro_collector_url, fn -> "/-/faro" end)

    html = render_component(&LayoutComponents.head_analytics_scripts/1, %{page_section: "marketing"})
    content_security_policy = Router.csp_opts(%{})

    assert html =~ ~s("enabled":true)
    assert html =~ ~s("collector_url":"/-/faro")
    assert html =~ ~s("page_section":"marketing")
    assert html =~ ~s("app_name":"tuist-web")

    refute html =~ "<script src"
    refute Keyword.fetch!(content_security_policy, :script_src_elem) =~ "grafana"
    refute Keyword.fetch!(content_security_policy, :connect_src) =~ "grafana"
  end

  test "loads Glossia independently on every hosted production surface without a Faro collector" do
    stub(Tuist.Environment, :prod?, fn -> true end)
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
    stub(Tuist.Environment, :analytics_enabled?, fn -> false end)
    stub(Tuist.Environment, :faro_collector_url, fn -> nil end)

    for section <- ["marketing", "docs", "dashboard", "api-docs"] do
      html = render_component(&LayoutComponents.head_analytics_scripts/1, %{page_section: section})
      script = html |> Floki.parse_fragment!() |> Floki.find("script[src]") |> hd()

      assert Floki.attribute(script, "src") == ["https://cdn.glossia.ai/web.js"]
      assert Floki.attribute(script, "data-domain") == ["tuist.dev"]
      assert Floki.attribute(script, "async") == ["async"]
      assert html =~ ~s("enabled":false)
    end

    policy = Router.csp_opts(%{})
    assert Keyword.fetch!(policy, :script_src_elem) =~ "https://cdn.glossia.ai"
    assert Keyword.fetch!(policy, :connect_src) =~ "https://cdn.glossia.ai"
  end

  test "omits Glossia outside production and on self-hosted installations" do
    for {production?, hosted?} <- [{false, true}, {true, false}] do
      stub(Tuist.Environment, :prod?, fn -> production? end)
      stub(Tuist.Environment, :tuist_hosted?, fn -> hosted? end)
      html = render_component(&LayoutComponents.head_analytics_scripts/1, %{page_section: "dashboard"})
      refute html =~ "cdn.glossia.ai"
    end
  end

  test "reports analytics disabled when no collector is configured" do
    stub(Tuist.Environment, :analytics_enabled?, fn -> false end)
    stub(Tuist.Environment, :faro_collector_url, fn -> nil end)

    html = render_component(&LayoutComponents.head_analytics_scripts/1, %{page_section: "marketing"})

    assert html =~ ~s("enabled":false)
  end

  test "omits analytics from embedded blog visualizations" do
    stub(Tuist.Environment, :prod?, fn -> true end)
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
    stub(Tuist.Environment, :analytics_enabled?, fn -> true end)
    stub(Tuist.Environment, :faro_collector_url, fn -> "/-/faro" end)

    html =
      render_component(&LayoutComponents.head_analytics_scripts/1, %{
        page_section: "marketing",
        analytics_disabled?: true
      })

    assert html =~ ~s("enabled":false)
    refute html =~ "cdn.glossia.ai"
  end
end
