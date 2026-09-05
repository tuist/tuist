defmodule Tuist.ShadowClickHouseRepo do
  @moduledoc """
  The in-cluster ClickHouse, as a read source, while ClickHouse Cloud is still
  the system of record (spec #73).

  Started only when `TUIST_CLICKHOUSE_BARE_METAL_URL` is set, which is only
  during the migration. Nothing calls it directly: `Tuist.ClickHouse.ReadRoute`
  names it as `Tuist.ClickHouseRepo`'s dynamic repository when the flag says
  reads have moved, so every read keeps the retry, telemetry and query
  behaviour that repository already gives it and only the connection pool
  underneath changes.

  Separate from `Tuist.ShadowIngestRepo` because the two carry different
  settings: this one is `readonly` with the per-query and per-user memory
  ceilings the read path depends on, and proving those hold against the
  in-cluster server is part of what the migration has to establish.
  """

  use Ecto.Repo,
    otp_app: :tuist,
    adapter: Ecto.Adapters.ClickHouse,
    read_only: true
end
