defmodule Atlas.ClickHouseRepo do
  @moduledoc """
  Read-only repository for ClickHouse queries.
  """

  use Ecto.Repo,
    otp_app: :atlas,
    adapter: Ecto.Adapters.ClickHouse,
    read_only: true
end
