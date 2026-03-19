defmodule Tuist.Repo do
  use Ecto.Repo,
    otp_app: :tuist,
    adapter: Ecto.Adapters.Postgres,
    pool_timeout: 15_000

  alias Tuist.Repo.PoolMetrics

  def running? do
    PoolMetrics.running?(__MODULE__)
  end

  def connection_pool_metrics do
    PoolMetrics.connection_pool_metrics(__MODULE__)
  end
end
