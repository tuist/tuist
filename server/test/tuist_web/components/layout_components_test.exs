defmodule TuistWeb.Components.LayoutComponentsTest do
  use ExUnit.Case, async: true

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
end
