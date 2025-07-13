defmodule TuistWeb.Bundles.UploadedByBadgeCell do
  @moduledoc """
  A component used to render a badge indicating who uploaded the bundle.
  """
  use Phoenix.Component
  use Noora

  attr :bundle, :map, required: true

  def bundle_uploaded_by_badge_cell(assigns) do
    ~H"""
    <%= if is_nil(@bundle.uploaded_by_account) || is_nil(@bundle.uploaded_by_account.user_id) do %>
      <.badge_cell label="CI" icon="settings" color="information" style="light-fill" />
    <% else %>
      <.badge_cell
        label={@bundle.uploaded_by_account.name}
        icon="user"
        color="primary"
        style="light-fill"
      />
    <% end %>
    """
  end
end
