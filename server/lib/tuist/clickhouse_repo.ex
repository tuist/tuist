defmodule Tuist.ClickHouseRepo do
  @moduledoc """
  Read-only ClickHouse repository for Tuist application.
  """

  use Ecto.Repo,
    otp_app: :tuist,
    adapter: Ecto.Adapters.ClickHouse,
    read_only: true
end
