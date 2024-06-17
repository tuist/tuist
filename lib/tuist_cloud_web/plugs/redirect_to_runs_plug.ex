defmodule TuistCloudWeb.RedirectToRunsPlug do
  @moduledoc """
  This plug redirects to the runs page if timescale is not available.
  """
  import Plug.Conn
  use TuistCloudWeb, :controller

  def init(opts), do: opts

  def call(
        %{
          path_params: %{
            "owner" => owner,
            "project" => project
          },
          path_info: [owner, project]
        } = conn,
        _opts
      ) do
    if TuistCloud.Repo.timescale_available?() do
      conn
    else
      conn
      |> redirect(to: ~p"/#{owner}/#{project}/runs")
      |> halt()
    end
  end

  def call(conn, _opts), do: conn
end
