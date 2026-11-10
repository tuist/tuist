defmodule Atlas.Environments.Provider do
  @moduledoc """
  Hosted tool execution contract. Implementations receive deployment-controlled
  configuration and an immutable owner/environment identity, never model keys.
  Start/stop/delete must be idempotent. Execute must never retry an ambiguous
  outcome. See `docs/environment-providers.md` for the wire and lifecycle contract.
  """

  # Atlas keeps contracts free of type annotations. The callback inventory still
  # lets the compiler check implementations declaring this behaviour.
  def behaviour_info(:callbacks), do: [start: 2, execute: 3, stop: 2, delete: 2]
  def behaviour_info(:optional_callbacks), do: []

  def configurations, do: Application.get_env(:atlas, :environment_providers, %{})

  def fetch(id) do
    case __MODULE__.configurations()[id] do
      %{module: module} = config when is_atom(module) -> {:ok, config}
      _ -> {:error, :environment_provider_unavailable}
    end
  end

  def catalog do
    __MODULE__.configurations()
    |> Enum.map(fn {id, config} -> %{id: id, name: config.name} end)
    |> Enum.sort_by(& &1.id)
  end

  def identity(environment),
    do: %{owner_id: environment.owner_id, environment_id: environment.id, generation: environment.version}
end
