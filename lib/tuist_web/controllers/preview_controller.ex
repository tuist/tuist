defmodule TuistWeb.PreviewController do
  use TuistWeb, :controller

  alias Tuist.Previews
  alias Tuist.Projects
  alias Tuist.Storage
  alias TuistWeb.Authorization
  alias TuistWeb.Errors.NotFoundError

  plug :assign_current_preview
       when action in [
              :download_preview,
              :download_qr_code_svg,
              :download_icon,
              :manifest
            ]

  plug Authorization, [:current_user, :read, :preview] when action in [:preview]

  def latest_badge(conn, _params) do
    conn
    |> redirect(to: ~p"/app/images/previews-badge.svg")
    |> halt()
  end

  def latest(conn, %{"account_handle" => account_handle, "project_handle" => project_handle} = _params) do
    with project when not is_nil(project) <-
           Projects.get_project_by_account_and_project_handles(account_handle, project_handle),
         latest_share_command_event when not is_nil(latest_share_command_event) <-
           Previews.get_latest_preview(project) do
      conn
      |> redirect(to: ~p"/#{account_handle}/#{project_handle}/previews/#{latest_share_command_event.id}")
      |> halt()
    else
      nil ->
        raise NotFoundError,
              "The page you are looking for doesn't exist or has been moved."
    end
  end

  def download_qr_code_svg(
        conn,
        %{"account_handle" => account_handle, "project_handle" => project_handle, "id" => preview_id} = _params
      ) do
    {:ok, qr_code_image} =
      ~p"/#{account_handle}/#{project_handle}/previews/#{preview_id}"
      |> url()
      |> QRCode.create(:low)
      |> QRCode.render()

    conn
    |> put_resp_content_type("image/svg+xml")
    |> send_resp(200, qr_code_image)
  end

  def download_qr_code_png(
        conn,
        %{"account_handle" => account_handle, "project_handle" => project_handle, "id" => preview_id} = _params
      ) do
    {:ok, qr_code_image} =
      ~p"/#{account_handle}/#{project_handle}/previews/#{preview_id}"
      |> url()
      |> QRCode.create(:low)
      |> QRCode.render(:png)

    conn
    |> put_resp_content_type("image/png")
    |> send_resp(200, qr_code_image)
  end

  def download_icon(
        conn,
        %{"account_handle" => account_handle, "project_handle" => project_handle, "id" => preview_id} = _params
      ) do
    object_key =
      Previews.get_icon_storage_key(%{
        account_handle: account_handle,
        project_handle: project_handle,
        preview_id: preview_id
      })

    if Storage.object_exists?(object_key) do
      conn
      |> put_resp_content_type("image/png")
      |> send_chunked(:ok)
      |> stream_object(object_key)
    else
      send_resp(conn, 404, "")
    end
  end

  defp stream_object(conn, object_key) do
    object_key
    |> Storage.stream_object()
    |> Enum.reduce_while(conn, fn chunk, conn ->
      case chunk(conn, chunk) do
        {:ok, conn} -> {:cont, conn}
        {:error, _reason} -> {:halt, conn}
      end
    end)
  end

  def download_archive(
        conn,
        %{"account_handle" => account_handle, "project_handle" => project_handle, "id" => preview_id} = _params
      ) do
    storage_key =
      Previews.get_storage_key(%{
        account_handle: account_handle,
        project_handle: project_handle,
        preview_id: preview_id
      })

    if Storage.object_exists?(storage_key) do
      send_resp(conn, 200, Storage.get_object_as_string(storage_key))
    else
      raise TuistWeb.Errors.NotFoundError, gettext("The preview archive doesn't exist or has expired.")
    end
  end

  def manifest(
        %{assigns: %{current_preview: preview}} = conn,
        %{"account_handle" => account_handle, "project_handle" => project_handle, "id" => preview_id} = _params
      ) do
    plist_content = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
        <dict>
            <key>items</key>
            <array>
                <dict>
                    <key>assets</key>
                    <array>
                        <dict>
                            <key>kind</key>
                            <string>software-package</string>
                            <key>url</key>
                            <string>#{url(~p"/#{account_handle}/#{project_handle}/previews/#{preview_id}/app.ipa")}</string>
                          </dict>
                    </array>
                    <key>metadata</key>
                    <dict>
                        <key>bundle-identifier</key>
                        <string>#{preview.bundle_identifier}</string>
                        <key>bundle-version</key>
                        <string>#{preview.version}</string>
                        <key>kind</key>
                        <string>software</string>
                        <key>title</key>
                        <string>App</string>
                    </dict>

                </dict>
            </array>
        </dict>
    </plist>
    """

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, plist_content)
  end

  def download_preview(
        %{assigns: %{current_preview: preview}} = conn,
        %{"account_handle" => account_handle, "project_handle" => project_handle} = _params
      ) do
    expires_in = 3600

    url =
      Storage.generate_download_url(
        Previews.get_storage_key(%{
          account_handle: account_handle,
          project_handle: project_handle,
          preview_id: preview.id
        }),
        expires_in: expires_in
      )

    conn
    |> redirect(external: url)
    |> halt()
  end

  defp assign_current_preview(%{params: %{"id" => preview_id}} = conn, _opts) do
    case Previews.get_preview_by_id(preview_id) do
      {:error, :not_found} ->
        raise NotFoundError, "Preview not found."

      {:ok, preview} ->
        assign(conn, :current_preview, preview)

      {:error, _} ->
        raise NotFoundError,
              "Preview not found."
    end
  end
end
