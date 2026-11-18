defmodule TuistWeb.DeviceCodeHTML do
  @moduledoc false

  use TuistWeb, :html
  use Noora

  embed_templates "device_code_html/*"

  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  slot :inner_block

  def device_code_frame(assigns) do
    ~H"""
    <div id="device-code">
      <div data-part="wrapper">
        <div data-part="frame">
          <div data-part="content">
            <.tuist_mark data-part="logo" aria-label={dgettext("dashboard_auth", "Tuist logo")} />
            <div data-part="dots">
              <.dots_light />
              <.dots_dark />
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
