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

  test "renders the analytics config the Faro Web SDK reads, and needs no third-party origin in the content security policy" do
    stub(Tuist.Environment, :analytics_enabled?, fn -> true end)
    stub(Tuist.Environment, :faro_collector_url, fn -> "/-/faro" end)

    html = render_component(&LayoutComponents.head_analytics_scripts/1, %{page_section: "marketing"})
    content_security_policy = Router.csp_opts(%{})

    assert html =~ ~s("enabled":true)
    assert html =~ ~s("collector_url":"/-/faro")
    assert html =~ ~s("page_section":"marketing")
    assert html =~ ~s("app_name":"tuist-web")

    # The SDK is bundled into our own JavaScript rather than fetched from a CDN,
    # so nothing here may add a script or connect origin.
    refute html =~ "<script src"
    refute Keyword.fetch!(content_security_policy, :script_src_elem) =~ "grafana"
    refute Keyword.fetch!(content_security_policy, :connect_src) =~ "grafana"
  end

  test "reports analytics disabled when no collector is configured" do
    stub(Tuist.Environment, :analytics_enabled?, fn -> false end)
    stub(Tuist.Environment, :faro_collector_url, fn -> nil end)

    html = render_component(&LayoutComponents.head_analytics_scripts/1, %{page_section: "marketing"})

    assert html =~ ~s("enabled":false)
  end

  test "omits analytics from embedded blog visualizations" do
    stub(Tuist.Environment, :analytics_enabled?, fn -> true end)
    stub(Tuist.Environment, :faro_collector_url, fn -> "/-/faro" end)

    html =
      render_component(&LayoutComponents.head_analytics_scripts/1, %{
        page_section: "marketing",
        analytics_disabled?: true
      })

    assert html =~ ~s("enabled":false)
  end
end
