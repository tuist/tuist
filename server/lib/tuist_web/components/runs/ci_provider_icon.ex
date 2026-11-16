defmodule TuistWeb.Runs.CIProviderIcon do
  @moduledoc """
  Icon for buttons linking to a run's CI run: the provider's logo when Noora has
  one, otherwise a generic external-link icon.
  """
  use TuistWeb, :html
  use Noora

  attr :provider, :any, required: true

  def ci_provider_icon(assigns) do
    assigns = assign(assigns, :provider, to_string(assigns.provider))

    ~H"""
    <%= case @provider do %>
      <% "github" -> %>
        <.brand_github />
      <% "gitlab" -> %>
        <.brand_gitlab />
      <% "bitrise" -> %>
        <.brand_bitrise />
      <% "buildkite" -> %>
        <.brand_buildkite />
      <% _ -> %>
        <.external_link />
    <% end %>
    """
  end
end
