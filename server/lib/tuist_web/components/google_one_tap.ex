defmodule TuistWeb.GoogleOneTap do
  @moduledoc false
  use TuistWeb, :html

  alias Tuist.Environment

  def enabled?(current_user) do
    is_nil(current_user) and Environment.google_auth_enabled?() and Environment.google_oauth_configured?()
  end

  attr :current_user, :any, default: nil

  attr :live, :boolean, default: false

  def prompt(assigns) do
    assigns = assign(assigns, :enabled?, enabled?(assigns.current_user))

    ~H"""
    <div
      :if={@enabled?}
      id="google-one-tap"
      data-static-hook={if !@live, do: "GoogleOneTap"}
      phx-hook={if @live, do: "GoogleOneTap"}
      phx-update={if @live, do: "ignore"}
      data-start-url={~p"/auth/google/one-tap/start"}
      hidden
    >
      <.form for={%{}} action={~p"/auth/google/one-tap"}>
        <input type="hidden" name="credential" />
      </.form>
    </div>
    """
  end
end
