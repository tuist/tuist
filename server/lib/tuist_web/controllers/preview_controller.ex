defmodule TuistWeb.PreviewController do
  use TuistWeb, :controller

  alias Tuist.AppBuilds
  alias Tuist.Storage
  alias TuistWeb.Authorization
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Plugs.LoaderPlug

  plug LoaderPlug

  plug :assign_current_preview
       when action in [
              :download_qr_code_svg,
              :download_icon,
              :download_preview,
              :download_archive,
              :manifest
            ]

  plug Authorization, [:current_user, :read, :preview] when action in [:preview]

  def latest_badge(conn, _params) do
    conn
    |> redirect(to: ~p"/app/images/previews-badge.svg")
    |> halt()
  end

  def latest(
        %{assigns: %{selected_project: project}} = conn,
        %{"account_handle" => account_handle, "project_handle" => project_handle} = params
      ) do
    bundle_id = params["bundle-id"]
    latest_previews = AppBuilds.latest_previews_with_distinct_bundle_ids(project)

    latest_preview =
      if is_nil(bundle_id) do
        List.first(latest_previews)
      else
        Enum.find(latest_previews, fn preview -> preview.bundle_identifier == bundle_id end)
      end

    case latest_preview do
      nil ->
        raise NotFoundError,
              "The page you are looking for doesn't exist or has been moved."

      preview ->
        conn
        |> redirect(to: ~p"/#{account_handle}/#{project_handle}/previews/#{preview.id}")
        |> halt()
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
    |> put_resp_content_type("image/png", nil)
    |> send_resp(200, qr_code_image)
  end

  def download_icon(
        %{assigns: %{selected_account: account}} = conn,
        %{"account_handle" => account_handle, "project_handle" => project_handle, "id" => preview_id} = _params
      ) do
    object_key =
      AppBuilds.icon_storage_key(%{
        account_handle: account_handle,
        project_handle: project_handle,
        preview_id: preview_id
      })

    if Storage.object_exists?(object_key, account) do
      conn
      |> put_resp_content_type("image/png", nil)
      |> send_chunked(:ok)
      |> stream_object(object_key, account)
    else
      send_resp(conn, 404, "")
    end
  end

  defp stream_object(conn, object_key, account) do
    object_key
    |> Storage.stream_object(account)
    |> Enum.reduce_while(conn, fn chunk, conn ->
      case chunk(conn, chunk) do
        {:ok, conn} -> {:cont, conn}
        {:error, _reason} -> {:halt, conn}
      end
    end)
  end

  def download_archive(
        %{assigns: %{current_preview: preview, selected_account: account}} = conn,
        %{"account_handle" => account_handle, "project_handle" => project_handle} = _params
      ) do
    app_build = AppBuilds.latest_ipa_app_build_for_preview(preview)

    storage_key =
      app_build &&
        AppBuilds.storage_key(%{
          account_handle: account_handle,
          project_handle: project_handle,
          app_build_id: app_build.id
        })

    if is_nil(app_build) or not Storage.object_exists?(storage_key, account) do
      raise NotFoundError, dgettext("dashboard", "The preview ipa doesn't exist or has expired.")
    end

    send_resp(conn, :ok, Storage.get_object_as_string(storage_key, account))
  end

  def manifest(
        %{assigns: %{current_preview: preview}} = conn,
        %{"account_handle" => account_handle, "project_handle" => project_handle} = _params
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
                            <string>#{url(~p"/#{account_handle}/#{project_handle}/previews/#{preview.id}/app.ipa")}</string>
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
        %{assigns: %{current_preview: preview, selected_account: account}} = conn,
        %{"account_handle" => account_handle, "project_handle" => project_handle} = _params
      ) do
    app_builds = preview.app_builds

    conn =
      conn
      |> put_resp_content_type("application/zip")
      |> put_resp_header(
        "content-disposition",
        "attachment; filename=\"preview-#{preview.id}.zip\""
      )
      |> send_chunked(200)

    zip_stream =
      app_builds
      |> Enum.map(fn app_build ->
        storage_key =
          AppBuilds.storage_key(%{
            account_handle: account_handle,
            project_handle: project_handle,
            app_build_id: app_build.id
          })

        content_stream = Storage.stream_object(storage_key, account)
        filename = "#{app_build.id}.zip"

        Zstream.entry(filename, content_stream)
      end)
      |> Zstream.zip()

    Enum.reduce_while(zip_stream, conn, fn chunk, conn ->
      case chunk(conn, chunk) do
        {:ok, conn} -> {:cont, conn}
        {:error, _reason} -> {:halt, conn}
      end
    end)
  end

  defp assign_current_preview(%{params: %{"id" => preview_id}} = conn, _opts) do
    case AppBuilds.preview_by_id(preview_id, preload: :app_builds) do
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
