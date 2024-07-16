defmodule Tuist.Repo do
  use Ecto.Repo,
    otp_app: :tuist,
    adapter: Ecto.Adapters.Postgres,
    pool_timeout: 15_000

  def timescale_available?() do
    query = """
    SELECT EXISTS (
      SELECT 1
      FROM pg_extension
      WHERE extname = 'timescaledb'
    )
    """

    case Ecto.Adapters.SQL.query!(__MODULE__, query, []) do
      %{rows: [[true]]} -> true
      %{rows: [[false]]} -> false
    end
  end
end
