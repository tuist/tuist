defmodule TuistWeb.Plugs.RequireCoveragePlug do
  @moduledoc """
  Keeps the coverage and test selection API to the projects whose build
  system reports coverage (`Tuist.Tests.Coverage.supported?/1`). Runs after
  `TuistWeb.Plugs.LoaderPlug`, which assigns the project. For any other
  project the endpoints answer 404, as if they did not exist.
  """

  @behaviour Plug

  import Plug.Conn

  alias Tuist.Tests.Coverage

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{assigns: %{selected_project: project}} = conn, _opts) do
    if Coverage.supported?(project), do: conn, else: not_enabled(conn)
  end

  def call(conn, _opts), do: not_enabled(conn)

  defp not_enabled(conn) do
    conn
    |> put_status(:not_found)
    |> Phoenix.Controller.json(%{message: "Code coverage isn't available for this project's build system."})
    |> halt()
  end
end
