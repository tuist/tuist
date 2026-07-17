defmodule TuistWeb.AgentAuthHTML do
  @moduledoc false

  use TuistWeb, :html
  use Noora

  embed_templates "agent_auth_html/*"

  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :appearance, :string, default: nil
  slot :inner_block

  def auth_frame(assigns) do
    ~H"""
    <div id="agent-auth">
      <div data-part="wrapper">
        <div data-part="frame">
          <div data-part="content">
            <img
              src={~p"/images/tuist_logo_32x32@2x.png"}
              alt="Tuist logo"
              data-part="logo"
              decoding="async"
            />
            <div data-part="dots">
              <.dots_light />
              <.dots_dark />
            </div>
            <div :if={@appearance} data-part="status-icon" data-appearance={@appearance}>
              <%= case @appearance do %>
                <% "success" -> %>
                  <.circle_check />
                <% "warning" -> %>
                  <.alert_triangle />
                <% _ -> %>
                  <.alert_circle />
              <% end %>
            </div>
            <div data-part="header">
              <h1 data-part="title">{@title}</h1>
              <span data-part="subtitle">{@subtitle}</span>
            </div>
            {render_slot(@inner_block)}
          </div>
        </div>
      </div>

      <div data-part="background">
        <div data-part="top-right-gradient"></div>
        <div data-part="bottom-left-gradient"></div>
        <div data-part="shell"><.shell /></div>
      </div>
      <.terms_and_privacy />
    </div>
    """
  end
end
