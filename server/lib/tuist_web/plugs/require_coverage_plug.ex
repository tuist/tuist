defmodule TuistWeb.Plugs.RequireCoveragePlug do
  @moduledoc """
  Keeps the coverage and test selection API behind the account's early access
  flag (`Tuist.FeatureFlags.xcode_coverage_enabled?/1`). Runs after
  `TuistWeb.Plugs.LoaderPlug`, which assigns the account. While the flag is
  off the endpoints answer 404, as if they did not exist.
  """

  @behaviour Plug

  import Plug.Conn

  alias Tuist.FeatureFlags

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{assigns: %{selected_account: account}} = conn, _opts) do
    if FeatureFlags.xcode_coverage_enabled?(account), do: conn, else: not_enabled(conn)
  end

  def call(conn, _opts), do: not_enabled(conn)

  defp not_enabled(conn) do
    conn
    |> put_status(:not_found)
    |> Phoenix.Controller.json(%{message: "Code coverage is in early access and is not enabled for this account."})
    |> halt()
  end
end
