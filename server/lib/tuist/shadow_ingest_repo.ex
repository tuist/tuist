defmodule Tuist.ShadowIngestRepo do
  @moduledoc """
  The in-cluster ClickHouse, as a write destination, while ClickHouse Cloud is
  still the system of record (spec #73).

  Started only when `TUIST_CLICKHOUSE_BARE_METAL_URL` is set, which is only
  during the migration. Everything that writes to it does so through
  `Tuist.IngestRepo`, which mirrors its writes here and swallows the failures:
  nothing customer-facing may depend on this repository being reachable, and
  nothing reads from it. Reads move separately, behind a flag, once the data
  has been shown to agree.
  """

  use Ecto.Repo,
    otp_app: :tuist,
    adapter: Ecto.Adapters.ClickHouse
end
