defmodule Tuist.ClickHouseRepo do
  @moduledoc """
  Read-only ClickHouse repository for Tuist application.
  """

  use Ecto.Repo,
    otp_app: :tuist,
    adapter: Ecto.Adapters.ClickHouse,
    read_only: true

  alias Tuist.Repo.PoolMetrics

  def running? do
    PoolMetrics.running?(__MODULE__)
  end

  def connection_pool_metrics do
    PoolMetrics.connection_pool_metrics(__MODULE__)
  end
end
