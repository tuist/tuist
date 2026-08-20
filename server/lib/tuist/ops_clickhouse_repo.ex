defmodule Tuist.OpsClickHouseRepo do
  @moduledoc """
  Isolated ClickHouse repository for internal operator queries.

  Production credentials belong to a dedicated ClickHouse user whose grants
  are limited to application tables and required system table metadata.
  """

  use Ecto.Repo,
    otp_app: :tuist,
    adapter: Ecto.Adapters.ClickHouse,
    read_only: true
end
