defmodule Atlas.Automations.Plan do
  @moduledoc "A bounded ordered plan with explicit run-local data references."

  alias Atlas.Automations.Behavior
  alias Atlas.Automations.Catalog
  alias Atlas.Automations.Composition
  alias Atlas.Automations.DomainAccess
  alias Atlas.Automations.DomainRegistry
  alias Atlas.Repo
  alias Atlas.Users.User

  def compile(%{"steps" => steps} = plan) when is_list(steps) and length(steps) in 1..32 do
    if Map.keys(plan) == ["steps"] do
      Enum.reduce_while(steps, {:ok, [], []}, fn step, {:ok, compiled, ids} ->
        case compile_step(step, ids, compiled) do
          {:ok, result} -> {:cont, {:ok, compiled ++ [result], ids ++ [step["id"]]}}
          error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, compiled, _} ->
          plan = %{"steps" => compiled}
          permissions = DomainAccess.permissions(compiled)
          {:ok, if(permissions == [], do: plan, else: Map.put(plan, "read_permissions", permissions))}

        error ->
          error
      end
    else
      {:error, "A plan must contain only steps."}
    end
  end

  def compile(_), do: {:error, "A plan requires between 1 and 32 ordered steps."}

  def resolve(%{"$ref" => path} = value, input, outputs) when map_size(value) == 1 and is_binary(path) do
    get_path(path, input, outputs)
  end

  def resolve(map, input, outputs) when is_map(map) do
    Enum.reduce_while(map, {:ok, %{}}, fn {key, item}, {:ok, acc} ->
      case resolve(item, input, outputs) do
        {:ok, resolved} -> {:cont, {:ok, Map.put(acc, key, resolved)}}
        error -> {:halt, error}
      end
    end)
  end

  def resolve(list, input, outputs) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn item, {:ok, acc} ->
      case resolve(item, input, outputs) do
        {:ok, resolved} -> {:cont, {:ok, acc ++ [resolved]}}
        error -> {:halt, error}
      end
    end)
  end

  def resolve(other, _input, _outputs), do: {:ok, other}

  defp compile_step(%{"id" => id} = step, ids, compiled) when is_binary(id) do
    cond do
      not Regex.match?(~r/^[a-z][a-z0-9_]{0,63}$/, id) or id in ids ->
        {:error, "Step IDs must be unique lowercase identifiers."}

      not valid_references?(step["inputs"] || %{}, ids) ->
        {:error, "References may only use input or preceding step outputs."}

      step["type"] == "approval" ->
        compile_approval(step)

      true ->
        compile_action(step, compiled)
    end
  end

  defp compile_step(_, _, _), do: {:error, "Every step requires an id."}

  defp compile_approval(step) do
    reviewer = step["reviewer_id"]

    with true <- Enum.all?(Map.keys(step), &(&1 in ~w(id type reviewer_id inputs))),
         true <- is_map(step["inputs"]),
         {:ok, _} <- Ecto.UUID.cast(reviewer),
         %User{} <- Repo.get(User, reviewer) do
      {:ok, Map.take(step, ~w(id type reviewer_id inputs))}
    else
      _ -> {:error, "An approval requires object inputs and an existing reviewer_id."}
    end
  end

  defp compile_action(step, compiled) do
    with true <- Enum.all?(Map.keys(step), &(&1 in ~w(id behavior inputs))),
         true <- is_binary(step["behavior"]) and is_map(step["inputs"]),
         {:ok, behavior} <- snapshot(step["behavior"]),
         :ok <- composition(step["inputs"], behavior, compiled) do
      {:ok, %{"id" => step["id"], "type" => "action", "inputs" => step["inputs"], "behavior" => behavior}}
    else
      {:error, _} = error -> error
      _ -> {:error, "An action requires a behavior and object inputs."}
    end
  end

  defp composition(input, behavior, compiled) do
    case DomainRegistry.fetch(behavior["type"], behavior["version"]) do
      {:ok, _} -> Composition.validate(input, behavior["input_schema"], compiled)
      _ -> :ok
    end
  end

  defp snapshot(name) do
    case if(byte_size(name) == 36, do: Ecto.UUID.cast(name), else: :error) do
      {:ok, id} ->
        case Repo.get(Behavior, id) do
          nil -> {:error, "Behavior not found."}
          behavior -> Catalog.snapshot(behavior)
        end

      :error ->
        Catalog.builtin(name)
    end
  end

  defp valid_references?(%{"$ref" => path} = value, ids) do
    map_size(value) == 1 and is_binary(path) and
      case String.split(path, ".") do
        ["input" | _] -> true
        ["steps", id | _] -> id in ids
        _ -> false
      end
  end

  defp valid_references?(value, ids) when is_map(value), do: Enum.all?(Map.values(value), &valid_references?(&1, ids))
  defp valid_references?(value, ids) when is_list(value), do: Enum.all?(value, &valid_references?(&1, ids))
  defp valid_references?(_, _), do: true

  defp get_path(path, input, outputs) do
    Enum.reduce_while(String.split(path, "."), {:ok, %{"input" => input, "steps" => outputs}}, fn key, {:ok, value} ->
      case value do
        %{^key => next} -> {:cont, {:ok, next}}
        _ -> {:halt, {:error, "A referenced input or step output is missing."}}
      end
    end)
  end
end
