defmodule TuistWeb.Previews.AppPreview do
  @moduledoc """
  Component to render a preview of an app.
  """
  use TuistWeb, :live_component
  use TuistWeb.Noora

  import TuistWeb.Previews.PlatformBadge
  import TuistWeb.Previews.RunButton

  attr :preview, :map, required: true
  attr :user_agent, :map, required: true

  def app_preview(assigns) do
    ~H"""
    <.link
      navigate={
        ~p"/#{@preview.project.account.name}/#{@preview.project.name}/previews/#{@preview.id}"
      }
      class="tuist-app-preview"
    >
      <div data-part="card">
        <img
          src={
            ~p"/#{@preview.project.account.name}/#{@preview.project.name}/previews/#{@preview.id}/icon.png"
          }
          onerror={"this.src='#{url(~p"/app/images/app-icon-placeholder.svg")}';"}
          alt={
            gettext("%{app_name} icon",
              app_name: @preview.display_name
            )
          }
          data-part="icon"
          id={"tuist-app-preview-#{@preview.id}"}
          phx-hook="ImageFallback"
          data-fallback-src={url(~p"/app/images/app-icon-placeholder.svg")}
        />
        <div data-part="metadata">
          <%= if assigns[:app_name] do %>
            <span data-part="title">{@app_name}</span>
          <% else %>
            <span data-part="title">
              {@preview.display_name}
            </span>
          <% end %>
          <div data-part="extra-metadata">
            <.platform_badge preview={@preview} />
            <div data-part="time">
              <div data-part="icon">
                <.history />
              </div>
              <span data-part="label">
                <% relative_date =
                  case Timex.from_now(@preview.inserted_at) |> String.split(" ") do
                    [number, unit, relative] -> number <> (unit |> String.at(0)) <> " " <> relative
                    _ -> Timex.from_now(@preview.inserted_at)
                  end %>
                {relative_date}
              </span>
            </div>
          </div>
        </div>
        <object><.run_button preview={@preview} user_agent={@user_agent} /></object>
      </div>
    </.link>
    """
  end
end
