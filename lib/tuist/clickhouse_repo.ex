defmodule Tuist.ClickHouseRepo do
  @moduledoc """
  ClickHouse repository for Tuist application.
  """

  use Ecto.Repo,
    otp_app: :tuist,
    adapter: Ecto.Adapters.ClickHouse
end
