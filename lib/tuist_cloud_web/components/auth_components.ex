defmodule TuistCloudWeb.AuthComponents do
  @moduledoc """
  Auth components for Tuist
  """

  use Phoenix.Component
  import TuistCloudWeb.CoreComponents

  attr(:title, :string, required: true)
  attr(:subtitle, :string, required: true)

  slot(:icon, required: false, default: nil)

  def auth_header(assigns) do
    ~H"""
    <.decorative_background class="auth-page__background" />
    <.stack class="auth-header" gap="3xl">
      <%= if !Enum.empty?(@icon) do %>
        <%= render_slot(@icon) %>
      <% else %>
        <img class="auth-header__logo" src="/images/tuist_logo_32x32@2x.png" />
      <% end %>
      <.stack gap="lg">
        <h5 class="auth-header__title font--semibold color--text-primary">
          <%= @title %>
        </h5>
        <p class="text--medium color--text-tertiary">
          <%= @subtitle %>
        </p>
      </.stack>
    </.stack>
    """
  end
end
