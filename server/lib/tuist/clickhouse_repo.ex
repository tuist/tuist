defmodule Tuist.ClickHouseRepo do
  @moduledoc """
  Read-only ClickHouse repository for Tuist application.
  """

  @default_dynamic_repo if Mix.env() == :test, do: Tuist.IngestRepo, else: __MODULE__

  use Ecto.Repo,
    otp_app: :tuist,
    adapter: Ecto.Adapters.ClickHouse,
    read_only: true,
    default_dynamic_repo: @default_dynamic_repo
end
