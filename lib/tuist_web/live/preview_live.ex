defmodule TuistWeb.PreviewLive do
  alias Tuist.Authorization
  use TuistWeb, :live_view

  alias Tuist.Previews

  def mount(
        %{
          "id" => preview_id,
          "account_handle" => account_handle,
          "project_handle" => project_handle
        } = _params,
        _session,
        socket
      ) do
    preview =
      get_current_preview(preview_id)

    layout =
      if TuistWeb.Authentication.authenticated?(socket.assigns) do
        {TuistWeb.Layouts, :project}
      else
        false
      end

    if not Authorization.can(
         socket.assigns.current_user,
         :read,
         preview
       ) do
      raise TuistWeb.Errors.NotFoundError,
            "Preview not found."
    end

    {
      :ok,
      socket
      |> assign(:account_handle, account_handle)
      |> assign(:project_handle, project_handle)
      |> assign(
        :head_title,
        gettext("%{display_name} · Tuist", display_name: preview.display_name)
      )
      |> assign(
        :head_description,
        "Easily run a preview of #{preview.display_name}"
      )
      |> assign(
        :preview,
        preview
      )
      |> assign(
        :preview_download_device_url,
        "itms-services://?action=download-manifest&url=#{url(~p"/#{account_handle}/#{project_handle}/previews/#{preview.id}/manifest.plist")}"
      )
      |> assign(
        :user_agent_os_family,
        case UAParser.parse(get_connect_info(socket, :user_agent)) do
          %UAParser.UA{os: %UAParser.OperatingSystem{family: family}} -> family
          _ -> nil
        end
      )
      |> assign(
        :supported_platforms,
        case Previews.get_supported_platforms_case_values(preview) do
          [] -> gettext("Unknown")
          supported_platforms -> supported_platforms |> Enum.join(", ")
        end
      ),
      layout: layout
    }
  end

  attr(:title, :string, required: true)
  attr(:value, :string, required: true)

  def preview_metadata_item(assigns) do
    ~H"""
    <div class="preview__extra-metadata-item">
      <p class="preview__extra-metadata-item__title">
        {@title}
      </p>
      <p class="preview__extra-metadata-item__value">
        {@value}
      </p>
    </div>
    """
  end

  defp get_current_preview(preview_id) do
    preview = Previews.get_preview_by_id(preview_id, preload: [:command_event, :project])

    if is_nil(preview) do
      raise TuistWeb.Errors.NotFoundError,
            "Preview not found."
    end

    preview
  end
end
