defmodule Tuist.Ingestion.Capture do
  @moduledoc """
  Captures buffer submissions in the calling process for a durable publication.
  It never changes application configuration or intercepts other processes.
  """
  @key {:tuist, :ingestion_capture}
  @rows {__MODULE__, :rows}
  @effects {__MODULE__, :effects}

  def active?, do: not is_nil(Process.get(@key))

  def defer_or_run(effect, fun) do
    if active?(), do: Process.put(@effects, [effect | Process.get(@effects)]), else: fun.()
  end

  def run(fun) do
    if active?(), do: raise("nested ingestion capture")
    Process.put(@rows, [])
    Process.put(@effects, [])
    Process.put(@key, fn schema, rows -> Process.put(@rows, [{schema, rows} | Process.get(@rows)]) end)

    try do
      result = fun.()

      {result,
       @rows
       |> Process.get()
       |> Enum.reverse()
       |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
       |> Map.new(fn {schema, rows} -> {schema, List.flatten(rows)} end), @effects |> Process.get() |> Enum.reverse()}
    after
      Process.delete(@key)
      Process.delete(@rows)
      Process.delete(@effects)
    end
  end
end
