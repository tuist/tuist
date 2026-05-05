defmodule Tuist.Kura.DeploymentLogLine do
  @moduledoc """
  ClickHouse schema for per-line stdout/stderr captured by
  `Tuist.Kura.Workers.RolloutWorker`. Write-only via `Tuist.IngestRepo`;
  reads use a raw query in `Tuist.Kura.list_log_lines/2`.
  """
  use Ecto.Schema

  @primary_key false
  schema "kura_deployment_log_lines" do
    field :deployment_id, Ch, type: "UUID"
    field :sequence, Ch, type: "UInt64"
    field :stream, Ch, type: "Enum8('stdout' = 0, 'stderr' = 1)"
    field :line, :string
    field :inserted_at, Ch, type: "DateTime64(3)"
  end
end
