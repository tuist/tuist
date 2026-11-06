defmodule TuistEx.Cache.Plan do
  @moduledoc false

  @key {__MODULE__, :inputs}

  # This is a speculative lookup plan, never an installation/publication proof.
  def with_plan(callback) do
    previous = Process.get(@key)
    Process.put(@key, %{context: nil, entries: %{}})

    try do
      callback.()
    after
      restore(previous)
    end
  end

  def in_context(context, callback) do
    case Process.get(@key) do
      %{context: ^context} -> :ok
      %{} -> Process.put(@key, %{context: context, entries: %{}})
      nil -> :ok
    end

    callback.()
  end

  def fetch(key, callback) do
    case Process.get(@key) do
      nil ->
        callback.()

      %{entries: entries} ->
        case Map.fetch(entries, key) do
          {:ok, value} ->
            value

          :error ->
            value = callback.()
            plan = Process.get(@key)
            Process.put(@key, %{plan | entries: Map.put(plan.entries, key, value)})
            value
        end
    end
  end

  def clear do
    if plan = Process.get(@key), do: Process.put(@key, %{plan | entries: %{}})
    :ok
  end

  def invalidate(app) do
    if plan = Process.get(@key) do
      entries =
        Map.reject(plan.entries, fn
          {{_, %Mix.Dep{app: ^app}}, _} -> true
          _ -> false
        end)

      Process.put(@key, %{plan | entries: entries})
    end

    :ok
  end

  def fresh(callback) do
    previous = Process.get(@key)
    Process.delete(@key)

    try do
      callback.()
    after
      restore(previous)
    end
  end

  defp restore(nil), do: Process.delete(@key)
  defp restore(plan), do: Process.put(@key, plan)
end
