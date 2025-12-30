defmodule Tuist.Tasks do
  @moduledoc false
  @task_timeout 60_000

  def parallel_tasks(queries, opts \\ []) do
    max_concurrency = Keyword.get(opts, :max_concurrency, 3)

    queries
    |> Task.async_stream(fn fun -> fun.() end,
      max_concurrency: max_concurrency,
      timeout: @task_timeout
    )
    |> Enum.to_list()
    |> Enum.map(fn {:ok, result} -> result end)
  end
end
