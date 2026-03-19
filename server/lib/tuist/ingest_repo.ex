defmodule Tuist.IngestRepo do
  @moduledoc """
  Write-centric ClickHouse repository.
  """

  use Ecto.Repo,
    otp_app: :tuist,
    adapter: Ecto.Adapters.ClickHouse
end
