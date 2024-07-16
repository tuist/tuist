defmodule TuistWeb.RedirectToRunsPlug do
  @moduledoc """
  This plug redirects to the runs page if timescale is not available.
  """
  import Plug.Conn
  use TuistWeb, :controller

  def init(opts), do: opts

  def call(
        %{
          path_params: %{
            "account_handle" => account_handle,
            "project_handle" => project_handle
          },
          path_info: [account_handle, project_handle]
        } = conn,
        _opts
      ) do
    if Tuist.Repo.timescale_available?() do
      conn
    else
      conn
      |> redirect(to: ~p"/#{account_handle}/#{project_handle}/runs")
      |> halt()
    end
  end

  def call(conn, _opts), do: conn
end
