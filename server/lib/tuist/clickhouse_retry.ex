defmodule Tuist.ClickHouseRetry do
  @moduledoc """
  Server-side alias for `TuistCommon.ClickHouseRetry`.

  The retry logic used to live here and now lives in `tuist_common`
  so `cache/`, `registry/`, and any other Elixir service that talks
  to ClickHouse can share it. This module stays as a thin delegator
  to keep the ~30 in-tree call sites (`ClickHouseRepo`, `IngestRepo`,
  `Ingestion.Buffer`, plus tests) working without a churny rename.
  """

  defdelegate with_retry(fun), to: TuistCommon.ClickHouseRetry
  defdelegate with_retry(fun, opts), to: TuistCommon.ClickHouseRetry
  defdelegate with_result_retry(fun), to: TuistCommon.ClickHouseRetry
  defdelegate with_result_retry(fun, opts), to: TuistCommon.ClickHouseRetry
  defdelegate memory_limit_error?(error), to: TuistCommon.ClickHouseRetry
end
