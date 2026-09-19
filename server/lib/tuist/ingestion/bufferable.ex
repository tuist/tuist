defmodule Tuist.Ingestion.Bufferable do
  @moduledoc """
  Server-side alias for `TuistCommon.Ingestion.Bufferable`.

  Wraps the shared macro so schemas in this codebase can write

      use Tuist.Ingestion.Bufferable

  and pick up `:tuist` + `Tuist.IngestRepo` without repeating those
  on every schema. New callers outside this codebase should use
  `TuistCommon.Ingestion.Bufferable` directly.
  """

  defmacro __using__(_opts) do
    quote do
      use TuistCommon.Ingestion.Bufferable,
        otp_app: :tuist,
        repo: Tuist.IngestRepo
    end
  end

  defdelegate compile_time_prepare(schema), to: TuistCommon.Ingestion.Bufferable
end
