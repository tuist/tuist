defmodule TuistWeb.Plugs.RequireCoveragePlug do
  @moduledoc """
  Keeps the coverage and test selection API behind
  `Tuist.FeatureFlags.coverage_enabled?/3`: open to Mix projects, behind the
  account's early access flag for the others. Runs after
  `TuistWeb.Plugs.LoaderPlug`, which assigns the account and the project.
  While coverage is off the endpoints answer 404, as if they did not exist.
  """

  @behaviour Plug

  import Plug.Conn

  alias Tuist.FeatureFlags

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{assigns: %{selected_account: account, selected_project: project}} = conn, _opts) do
    if FeatureFlags.coverage_enabled?(account, project), do: conn, else: not_enabled(conn)
  end

  def call(conn, _opts), do: not_enabled(conn)

  defp not_enabled(conn) do
    conn
    |> put_status(:not_found)
    |> Phoenix.Controller.json(%{message: "Code coverage is in early access and is not enabled for this account."})
    |> halt()
  end
end
