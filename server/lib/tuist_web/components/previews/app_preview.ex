defmodule TuistWeb.Previews.AppPreview do
  @moduledoc """
  Component to render a preview of an app.
  """
  use TuistWeb, :live_component
  use Noora

  import TuistWeb.Previews.PlatformBadge
  import TuistWeb.Previews.RunButton

  attr :preview, :map, required: true
  attr :user_agent, :map, required: true

  def app_preview(assigns) do
    ~H"""
    <div class="tuist-app-preview">
      <img
        src={~p"/app/images/app-icon-placeholder.svg"}
        data-image-src={
          url(
            ~p"/#{@preview.project.account.name}/#{@preview.project.name}/previews/#{@preview.id}/icon.png"
          )
        }
        alt={dgettext("dashboard", "%{app_name} icon", app_name: @preview.display_name)}
        data-part="icon"
        id={"tuist-app-preview-#{@preview.id}"}
        phx-hook="ImageFallback"
        decoding="async"
      />
      <div data-part="metadata">
        <%= if assigns[:app_name] do %>
          <span data-part="title">{@app_name}</span>
        <% else %>
          <span data-part="title">
            {@preview.display_name}
          </span>
        <% end %>
        <span :if={release_notes_summary(@preview.release_notes)} data-part="release-notes-summary">
          {release_notes_summary(@preview.release_notes)}
        </span>
        <div data-part="extra-metadata">
          <%= for platform <- Enum.sort(@preview.supported_platforms) do %>
            <.platform_badge platform={platform} />
          <% end %>
          <div data-part="time">
            <div data-part="icon">
              <.history />
            </div>
            <span data-part="label">
              {Tuist.Utilities.DateFormatter.from_now(@preview.inserted_at)}
            </span>
          </div>
        </div>
      </div>
      <.run_button preview={@preview} user_agent={@user_agent} data-part="run-button" />
      <.link
        navigate={
          ~p"/#{@preview.project.account.name}/#{@preview.project.name}/previews/#{@preview.id}"
        }
        data-part="link"
      ></.link>
    </div>
    """
  end

  def release_notes_summary(nil), do: nil

  def release_notes_summary(notes) do
    case notes |> String.trim() |> String.split(~r/\R/u, parts: 2) |> hd() |> String.trim() do
      "" -> nil
      first_line -> first_line
    end
  end
end
