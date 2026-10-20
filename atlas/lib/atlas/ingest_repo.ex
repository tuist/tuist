defmodule Atlas.IngestRepo do
  @moduledoc """
  Write-only repository for ClickHouse ingestion.
  """

  use Ecto.Repo,
    otp_app: :atlas,
    adapter: Ecto.Adapters.ClickHouse
end
