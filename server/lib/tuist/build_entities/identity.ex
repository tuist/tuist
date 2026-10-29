defmodule Tuist.BuildEntities.Identity do
  @moduledoc """
  Identity contracts for build entities and the deterministic IDs derived from
  them.

  Each `{system, kind}` pair declares the ordered identity fields that make an
  entity the same across builds. The entity ID is a pure function of the
  project, system, kind and those fields, so producers never read before
  writing. Fields are length-prefixed before hashing, so `["a:b", "c"]` and
  `["a", "b:c"]` cannot collide, and the encoding carries a version so a future
  normalization change cannot silently merge histories.

  Kinds are strings at the public seam and are only ever matched against this
  fixed map; nothing here creates atoms from input.
  """

  @version "build-entity-v1"
  @observation_version "build-entity-observation-v1"

  @contracts %{
    gradle: %{"task" => ["root_project_name", "build_path", "task_path", "task_type"]},
    xcode: %{"module" => ["project", "target"]},
    once: %{"action" => ["target_id", "capability", "action_index"]},
    bazel: %{"action" => ["target_label", "mnemonic", "primary_output"]},
    mix: %{"file" => ["path"], "module" => ["module"]}
  }

  @systems Map.new(@contracts, fn {system, _} -> {Atom.to_string(system), system} end)

  def contracts, do: @contracts

  @doc """
  Resolves a system (atom or string) and kind (string) against the fixed
  contract map.
  """
  def resolve(system, kind) when is_binary(system), do: resolve(Map.get(@systems, system), kind)

  def resolve(system, kind) when is_atom(system) and is_binary(kind) do
    case @contracts |> Map.get(system, %{}) |> Map.fetch(kind) do
      {:ok, fields} -> {:ok, {system, kind, fields}}
      :error -> :error
    end
  end

  def resolve(_system, _kind), do: :error

  def fields(system, kind) do
    case resolve(system, kind) do
      {:ok, {_system, _kind, fields}} -> fields
      :error -> raise ArgumentError, "Unknown build entity #{inspect(system)}/#{inspect(kind)}"
    end
  end

  @doc """
  Returns the identity as an ordered list of `{field, value}` pairs, with every
  value normalized to a string. Missing values become `""`.
  """
  def normalize(system, kind, identity) when is_map(identity) do
    Enum.map(fields(system, kind), fn field -> {field, identity |> Map.get(field) |> to_value()} end)
  end

  def id(project_id, system, kind, identity) when is_integer(project_id) and is_map(identity) do
    values = system |> normalize(kind, identity) |> Enum.map(&elem(&1, 1))
    uuid([@version, Integer.to_string(project_id), Atom.to_string(system), kind | values])
  end

  @doc """
  Deterministic observation ID: the same execution reported twice yields the
  same ID, so duplicates collapse on merge and are dropped by `LIMIT 1 BY id`.
  `discriminator` distinguishes repeated executions of one entity within the
  same parent (an ordinal or a producer event ID).
  """
  def observation_id(entity_id, parent_id, discriminator) do
    uuid([@observation_version, entity_id, to_value(parent_id), to_value(discriminator)])
  end

  @doc """
  JSON encoding of the identity with keys in contract order, stored as the
  entity's identity string.
  """
  def encode(system, kind, identity) do
    pairs = normalize(system, kind, identity)
    "{" <> Enum.map_join(pairs, ",", fn {key, value} -> JSON.encode!(key) <> ":" <> JSON.encode!(value) end) <> "}"
  end

  defp uuid(components) do
    payload = Enum.map(components, fn component -> [<<byte_size(component)::32>>, component] end)
    <<a::48, _::4, b::12, _::2, c::62, _::binary>> = :crypto.hash(:sha256, payload)
    Ecto.UUID.cast!(<<a::48, 8::4, b::12, 2::2, c::62>>)
  end

  defp to_value(nil), do: ""
  defp to_value(value) when is_binary(value), do: value
  defp to_value(value) when is_integer(value), do: Integer.to_string(value)
  defp to_value(value) when is_atom(value), do: Atom.to_string(value)
end
