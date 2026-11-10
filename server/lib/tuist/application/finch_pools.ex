defmodule Tuist.Application.FinchPools do
  @moduledoc """
  Sizes the server's fallback HTTP pool from its configured download queues.
  """

  alias TuistCommon.FinchPools

  def default_pool_size(queues, configured_size) do
    queues
    |> download_queue_concurrencies()
    |> FinchPools.download_pool_size()
    |> max(configured_size)
  end

  defp download_queue_concurrencies(queues) when is_list(queues) do
    queues
    |> Keyword.take([:process_build, :process_xcresult])
    |> Enum.map(fn
      {_queue, limit} when is_integer(limit) -> limit
      # Paused queues still need capacity when the drain monitor resumes them.
      {_queue, opts} when is_list(opts) -> Keyword.fetch!(opts, :limit)
    end)
  end

  defp download_queue_concurrencies(_queues), do: []
end
