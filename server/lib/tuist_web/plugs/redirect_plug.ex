defmodule TuistWeb.RedirectPlug do
  @moduledoc """
  A generic redirect plug that preserves path parameters like account_handle and project_handle.

  ## Usage

      get "/binary-cache/cache-runs", RedirectPlug, to: "/module-cache/cache-runs"

  This will redirect from `/:account_handle/:project_handle/binary-cache/cache-runs`
  to `/:account_handle/:project_handle/module-cache/cache-runs`.
  """
  import Phoenix.Controller
  import Plug.Conn

  def init(opts) do
    opts
  end

  def call(conn, opts) do
    to_path = Keyword.fetch!(opts, :to)
    account_handle = conn.path_params["account_handle"]
    project_handle = conn.path_params["project_handle"]

    new_path = "/#{account_handle}/#{project_handle}#{to_path}"

    # Preserve query string if present
    new_path_with_query =
      if conn.query_string == "" do
        new_path
      else
        "#{new_path}?#{conn.query_string}"
      end

    conn
    |> put_status(:moved_permanently)
    |> redirect(to: new_path_with_query)
    |> halt()
  end
end
