defmodule Tuist.IngestRepo do
  @moduledoc """
  Write-only ClickHouse repository. Reads belong on
  `Tuist.ClickHouseRepo`.

  While the migration off ClickHouse Cloud is in progress (spec #73) every
  write here is also mirrored onto `Tuist.ShadowIngestRepo`, so that both
  servers hold the same new rows. See `Tuist.IngestRepo.ShadowWrite` for which
  statements are mirrored and why the fan-out lives in the repository rather
  than at the 40 call sites.
  """

  use Ecto.Repo,
    otp_app: :tuist,
    adapter: Ecto.Adapters.ClickHouse

  alias Tuist.ClickHouseRetry
  alias Tuist.IngestRepo.ShadowWrite

  # `query/3` and `query!/3` are injected by the adapter's own
  # `__before_compile__`, so they do not exist yet for `defoverridable` in
  # this module body. Deferring the override to a hook that runs afterwards is
  # the same approach `Tuist.ClickHouseRepo` takes for its retry wrapper.
  @before_compile ShadowWrite

  defoverridable insert_all: 2, insert_all: 3, insert: 1, insert: 2

  def insert_all(schema_or_source, entries, opts \\ []) do
    result = with_retry(fn -> super(schema_or_source, entries, opts) end)
    ShadowWrite.mirror_insert_all(schema_or_source, entries, opts)
    result
  end

  def insert(struct, opts \\ []) do
    result = with_retry(fn -> super(struct, opts) end)
    ShadowWrite.mirror_insert(struct, opts)
    result
  end

  defdelegate with_retry(fun), to: ClickHouseRetry
  defdelegate with_retry(fun, retries_left), to: ClickHouseRetry
end
