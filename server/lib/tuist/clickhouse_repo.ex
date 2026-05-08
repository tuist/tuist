defmodule Tuist.ClickHouseRepo do
  @moduledoc """
  Read-only ClickHouse repository for Tuist application.
  """

  use Ecto.Repo,
    otp_app: :tuist,
    adapter: Ecto.Adapters.ClickHouse,
    read_only: true,
    default_dynamic_repo: Application.compile_env(:tuist, [__MODULE__, :default_dynamic_repo], __MODULE__)

  alias Tuist.ClickHouseRetry

  defoverridable all: 1, all: 2, one: 1, one: 2

  def all(queryable, opts \\ []) do
    ClickHouseRetry.with_retry(fn -> super(queryable, opts) end)
  end

  def one(queryable, opts \\ []) do
    ClickHouseRetry.with_retry(fn -> super(queryable, opts) end)
  end
end
