defmodule TuistWeb.SSOLinkHTML do
  @moduledoc false

  use TuistWeb, :html
  use Noora

  embed_templates "sso_link_html/*"

  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  slot :inner_block

  def link_frame(assigns) do
    ~H"""
    <.auth_page id="sso-link" title={@title} subtitle={@subtitle}>
      {render_slot(@inner_block)}
    </.auth_page>
    """
  end
end
