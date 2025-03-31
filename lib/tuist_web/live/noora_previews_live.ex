defmodule TuistWeb.NooraPreviewsLive do
  use TuistWeb, :live_view
  use TuistWeb.Noora

  def mount(_params, _session, %{assigns: %{}} = socket) do
    {:ok, socket}
  end
end
