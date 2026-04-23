defmodule Tuist.ClickHouseRepo do
  @moduledoc """
  Read-only ClickHouse repository for Tuist application.
  """

  @default_dynamic_repo (
                          :tuist
                          |> Application.compile_env(__MODULE__, [])
                          |> Keyword.get(:default_dynamic_repo, __MODULE__)
                        )

  use Ecto.Repo,
    otp_app: :tuist,
    adapter: Ecto.Adapters.ClickHouse,
    read_only: true,
    default_dynamic_repo: @default_dynamic_repo
end
