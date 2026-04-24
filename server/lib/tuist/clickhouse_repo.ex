defmodule Tuist.ClickHouseRepo do
  @moduledoc """
  Read-only ClickHouse repository for Tuist application.
  """

  use Ecto.Repo,
    otp_app: :tuist,
    adapter: Ecto.Adapters.ClickHouse,
    read_only: true,
    default_dynamic_repo:
      :tuist
      |> Application.compile_env(__MODULE__, [])
      |> Keyword.get(:default_dynamic_repo, __MODULE__)
end
