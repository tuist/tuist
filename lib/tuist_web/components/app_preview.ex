defmodule TuistWeb.AppPreview do
  @moduledoc """
  Component to render a preview of an app.
  """
  use TuistWeb, :live_component
  use TuistWeb.Noora
  alias Tuist.Previews

  attr(:preview, :map, required: true)

  def app_preview(assigns) do
    ~H"""
    <div class="tuist-app-preview">
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
          <.badge
            :if={not Enum.empty?(@preview.supported_platforms)}
            size="small"
            label={Previews.get_supported_platforms_case_values(@preview) |> List.first()}
            color="neutral"
            style="light-fill"
          >
            <:icon>
              <.icon name={icon_name(@preview.supported_platforms)} />
            </:icon>
          </.badge>
          <div data-part="time">
            <div data-part="icon">
              <.history />
            </div>
            <span data-part="label">
              <% [number, unit, relative] = Timex.from_now(@preview.inserted_at) |> String.split(" ")
              relative_date = number <> (unit |> String.at(0)) <> " " <> relative %>
              {relative_date}
            </span>
          </div>
        </div>
      </div>
      <.button
        icon_only
        variant="secondary"
        size="small"
        href={
          {:tuist,
           "open-preview?server_url=#{TuistWeb.Endpoint.url()}&preview_id=#{@preview.id}&full_handle=#{@preview.project.account.name}/#{@preview.project.name}"}
        }
      >
        <.player_play />
      </.button>
    </div>
    """
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp icon_name(supported_platforms) do
    cond do
      Enum.member?(supported_platforms, :ios) -> "device_mobile"
      Enum.member?(supported_platforms, :ios_simulator) -> "device_mobile"
      Enum.member?(supported_platforms, :macos) -> "device_desktop"
      Enum.member?(supported_platforms, :tvos) -> "device_tv"
      Enum.member?(supported_platforms, :tvos_simulator) -> "device_tv"
      Enum.member?(supported_platforms, :watchos) -> "device_watch"
      Enum.member?(supported_platforms, :watch_os_simulator) -> "device_watch"
      Enum.member?(supported_platforms, :visionos) -> "device_vision_pro"
      Enum.member?(supported_platforms, :visionos_simulator) -> "device_vision_pro"
    end
  end
end
