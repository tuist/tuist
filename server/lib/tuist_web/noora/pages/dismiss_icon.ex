defmodule TuistWeb.Noora.Pages.DismissIcon do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Dismiss icon",
    description: "A compact close button for dismissing or removing the element it sits in.",
    components: [{Noora.DismissIcon, :dismiss_icon}],
    guidelines: [
      "Alerts, banners, modals, and tags already include a dismiss icon. Use it on its own only when you build a custom surface that can be closed.",
      "Use `small` in compact components such as tags and small alerts, and `large`, the default, everywhere else.",
      "Pass an event name to `on_dismiss` when the server decides what happens. To hide an element in the browser only, pass `phx-click` with `JS.hide`, as banners and alerts do.",
      ~s(The button always renders with `aria-label="Dismiss"` and `type="button"`, so it never submits a surrounding form.)
    ]

  alias Phoenix.LiveView.JS

  example "Sizes", description: "Large is the default." do
    ~H"""
    <.dismiss_icon size="small" />
    <.dismiss_icon size="large" />
    """
  end

  example "Hiding an element",
    description: "`phx-click` with `JS.hide` removes the surrounding element without a round trip to the server." do
    ~H"""
    <div id="dismiss-icon-notice" style="display: flex; align-items: center; gap: 8px;">
      <span>Selective testing skipped 312 tests in this run.</span>
      <.dismiss_icon size="small" phx-click={JS.hide(to: "#dismiss-icon-notice")} />
    </div>
    """
  end

  example "Disabled",
    description: "Disable it while the element cannot be dismissed, for example while a request is in flight." do
    ~H"""
    <.dismiss_icon size="small" disabled />
    <.dismiss_icon size="large" disabled />
    """
  end
end
