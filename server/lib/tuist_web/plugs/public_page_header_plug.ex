defmodule TuistWeb.Plugs.PublicPageHeaderPlug do
  @moduledoc ~S"""
  Marks responses whose URL is reachable without sign-in by setting the
  `x-tuist-public: 1` response header. A page is public when the project or
  account it lives under has `visibility: :public`, or when a preview is
  itself public.

  Cloudflare's Advanced Rate Limiting rule keys its counter on this header
  (counting expression `http.response.headers["x-tuist-public"][0] eq "1"`),
  so bot bombardment of public pages can be throttled at the edge without
  us maintaining a URL allowlist or syncing project state to Cloudflare
  out of band.

  Wire the appropriate function plug into each pipeline that serves a
  public-facing entity (import this module first, as the router already
  does for `TuistWeb.Authentication`):

      pipe_through [..., :mark_public_project_page, ...]
      pipe_through [..., :mark_public_account_page, ...]
      pipe_through [..., :mark_public_preview_page, ...]

  The header is set purely from the entity's own visibility. Whether the
  current request is signed in is irrelevant: the classification is "this
  URL is public", not "this request was anonymous".
  """
  import Plug.Conn

  alias Tuist.Accounts
  alias Tuist.AppBuilds
  alias Tuist.Projects

  @header "x-tuist-public"

  def mark_public_project_page(
        %{path_params: %{"account_handle" => account_handle, "project_handle" => project_handle}} = conn,
        _opts
      ) do
    case Projects.get_project_by_account_and_project_handles(account_handle, project_handle) do
      %{visibility: :public} -> put_public_header(conn)
      _ -> conn
    end
  end

  def mark_public_project_page(conn, _opts), do: conn

  def mark_public_account_page(%{path_params: %{"account_handle" => account_handle}} = conn, _opts) do
    case Accounts.get_account_by_handle(account_handle) do
      %{visibility: :public} -> put_public_header(conn)
      _ -> conn
    end
  end

  def mark_public_account_page(conn, _opts), do: conn

  def mark_public_preview_page(%{path_params: %{"id" => preview_id}} = conn, _opts) do
    case AppBuilds.preview_by_id(preview_id, preload: :project) do
      {:ok, preview} ->
        preview_visibility = preview.visibility || preview.project.default_previews_visibility

        if preview_visibility == :public or preview.project.visibility == :public,
          do: put_public_header(conn),
          else: conn

      _ ->
        conn
    end
  end

  def mark_public_preview_page(conn, _opts), do: conn

  defp put_public_header(conn), do: put_resp_header(conn, @header, "1")
end
