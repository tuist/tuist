defmodule Atlas.TestSupport.ProcessRegistry do
  @moduledoc false

  @name __MODULE__

  def put(namespace, value) do
    ensure_started()
    owner = self()

    Agent.update(@name, &Map.put(&1, {namespace, owner}, value))
    ExUnit.Callbacks.on_exit(fn -> delete(namespace, owner) end)
    :ok
  end

  def get(namespace, default \\ nil) do
    ensure_started()
    owner_pids = owner_pids()

    Agent.get(@name, fn values ->
      case owner_registered_value(values, namespace, owner_pids) do
        {:ok, value} -> value
        :error -> single_registered_value(values, namespace, default)
      end
    end)
  end

  def delete(namespace, owner \\ self()) do
    ensure_started()

    Agent.update(@name, &Map.delete(&1, {namespace, owner}))
    :ok
  end

  defp owner_registered_value(values, namespace, owner_pids) do
    Enum.find_value(owner_pids, :error, fn pid ->
      Map.fetch(values, {namespace, pid})
    end)
  end

  defp owner_pids do
    [self() | Process.get(:"$callers", [])]
  end

  defp single_registered_value(values, namespace, default) do
    values
    |> Enum.filter(fn {{entry_namespace, _pid}, _value} -> entry_namespace == namespace end)
    |> case do
      [{_key, value}] -> value
      _entries -> default
    end
  end

  defp ensure_started do
    case Agent.start(fn -> %{} end, name: @name) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end
end
