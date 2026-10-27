defmodule Tuist.Marketing.ReleaseMetadata do
  @moduledoc """
  Traces release lookup latency, including cache waits and cache-miss workers.
  """

  alias OpenTelemetry.Ctx
  alias OpenTelemetry.Tracer
  alias Tuist.KeyValueStore

  require Logger
  require Tracer

  def get_or_update(source, key, opts, fetch) when source in [:github, :github_page, :app_store] do
    Tracer.with_span "marketing.release_metadata.#{source}" do
      context = Ctx.get_current()
      started = System.monotonic_time(:millisecond)

      try do
        KeyValueStore.get_or_update(key, opts, fn ->
          # Cachex invokes misses in a worker. Carry only OTel context across
          # that boundary and restore the worker's context even on failure.
          token = Ctx.attach(context)

          try do
            Tracer.with_span "marketing.release_metadata.#{source}.fetch" do
              fetch.()
            end
          after
            Ctx.detach(token)
          end
        end)
      after
        duration = System.monotonic_time(:millisecond) - started

        if duration >= 1_000 do
          Logger.info("Slow release metadata #{source} lookup (#{duration}ms)")
        end
      end
    end
  end
end
