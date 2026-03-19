defmodule Tuist.IngestRepo do
  @moduledoc """
  Write-centric ClickHouse repository.
  """

  use Ecto.Repo,
    otp_app: :tuist,
    adapter: Ecto.Adapters.ClickHouse

  alias Tuist.Repo.PoolMetrics

  def running? do
    PoolMetrics.running?(__MODULE__)
  end

  def connection_pool_metrics do
    PoolMetrics.connection_pool_metrics(__MODULE__)
  end
end
