defmodule TuistWeb.LoginAnalyticsOptOutTest do
  # A crawler farm was following `Log in` links on every localised docs page and
  # landing on `/users/log_in?return_to=/<locale>/docs/...`. Every hit reported a
  # fresh Faro session with LCP dominated by TTFB, dragging the `tuist-web`
  # 24h p99 above 17s and firing the pathological-tail alert. The login page
  # has no product-meaningful LCP anyway (`context_element="#login>div"`), so
  # the two LiveViews behind that URL opt out of Faro entirely.
  use ExUnit.Case, async: false
  use Mimic

  import Phoenix.LiveViewTest

  setup :set_mimic_from_context

  setup do
    stub(Tuist.Environment, :analytics_enabled?, fn -> true end)
    stub(Tuist.Environment, :faro_collector_url, fn -> "/-/faro" end)
    # `UserLoginLive.mount/3` calls `Accounts.sso_configured?/0` which hits the
    # database. This test doesn't need a real answer; it only asserts on the
    # `analytics_disabled?` assign.
    stub(Tuist.Accounts, :sso_configured?, fn -> false end)
    :ok
  end

  test "UserLoginLive.mount/3 flags the layout to skip Faro" do
    socket = build_socket()

    {:ok, socket, _opts} = TuistWeb.UserLoginLive.mount(%{}, %{}, socket)

    assert render_analytics(socket.assigns) =~ ~s("enabled":false)
  end

  test "SSOLoginLive.mount/3 flags the layout to skip Faro" do
    socket = build_socket()

    {:ok, socket, _opts} = TuistWeb.SSOLoginLive.mount(%{}, %{}, socket)

    assert render_analytics(socket.assigns) =~ ~s("enabled":false)
  end

  defp build_socket do
    %Phoenix.LiveView.Socket{assigns: %{flash: %{}, __changed__: %{}}}
  end

  defp render_analytics(assigns) do
    render_component(
      &TuistWeb.LayoutComponents.head_analytics_scripts/1,
      Map.put(assigns, :page_section, "dashboard")
    )
  end
end
