defmodule Atlas.Automations.DomainRuntime do
  @moduledoc false
  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Automations.Approval
  alias Atlas.Automations.Contract
  alias Atlas.Automations.DomainRegistry
  alias Atlas.Automations.LocalOperations
  alias Atlas.MCP.Server
  alias Atlas.Repo
  alias Atlas.Search
  alias Atlas.Users
  alias Atlas.Users.User

  def execute(entry, behavior, input, actor, opts) do
    with :ok <- DomainRegistry.validate_snapshot(entry, behavior),
         :ok <- authorize(entry, actor),
         :ok <- Contract.validate(entry["input_schema"], input),
         :ok <- approval(entry, input, opts) do
      Repo.transaction(fn -> perform_transaction(entry, input, actor, opts) end)
    end
  end

  defp perform_transaction(entry, input, actor, opts) do
    Search.with_deferred_vectors(fn ->
      Audit.with_context(%{actor: actor, interface: "worker"}, fn -> perform(entry, input, actor, opts) end)
    end)
  end

  defp perform(entry, input, actor, opts) do
    case invoke(entry, input, actor) do
      {:ok, value} ->
        with {:ok, output, _} <- normalize(value, 65_536, 0),
             :ok <- Contract.validate(entry["output_schema"], output) do
          record(entry, actor, opts)
          output
        else
          _ -> Repo.rollback("The domain operation returned an invalid or oversized output.")
        end

      _ ->
        Repo.rollback("The domain operation could not complete.")
    end
  end

  def authorize(entry, %User{} = actor) do
    adapter = DomainRegistry.handler(entry)
    scopes_allowed = Enum.all?(entry["permissions"], &Users.has_scope?(actor, &1))
    adapter_allowed = adapter == LocalOperations or Server.workflow_tool_allowed?(actor, entry["source_tool"])
    if scopes_allowed and adapter_allowed, do: :ok, else: {:error, "The execution user lacks the domain permission."}
  end

  def authorize(_, _), do: {:error, "An authenticated execution user is required."}

  defp approval(%{"requires_approval" => false}, _input, _opts), do: :ok

  defp approval(entry, input, opts) do
    run_id = opts[:run_id]
    step_id = opts[:step_id]
    expected = %{"behavior" => entry["name"], "version" => entry["version"], "step_id" => step_id, "input" => input}

    approved =
      is_binary(run_id) and is_binary(step_id) and
        Repo.exists?(
          from a in Approval, where: a.run_id == ^run_id and a.status == "approved" and a.payload == ^expected
        )

    if approved,
      do: :ok,
      else: {:error, "This operation requires a prior approval bound to this step, behavior version and exact input."}
  end

  defp invoke(%{"action" => action}, input, actor), do: LocalOperations.execute(action, input, actor)

  defp invoke(entry, input, actor) do
    module = DomainRegistry.adapter(entry)
    module.execute(%{assigns: %{current_user: actor, audit_interface: "worker"}}, input)
  end

  defp record(entry, actor, opts) do
    Audit.record(
      "automation.domain_operation.completed",
      %{
        target_type: "automation_execution",
        target_id: opts[:run_id] || entry["name"],
        target_label: entry["name"],
        metadata: %{"behavior" => entry["name"], "version" => entry["version"], "step_id" => opts[:step_id]}
      },
      actor: actor,
      interface: "worker"
    )
  end

  defp normalize(_, bytes, depth) when bytes < 0 or depth > 32, do: :error
  defp normalize(%_{}, _, _), do: :error

  defp normalize(value, bytes, depth) when is_map(value) do
    Enum.reduce_while(value, {:ok, %{}, bytes - 2}, fn {key, item}, {:ok, acc, budget} ->
      key = if is_atom(key), do: Atom.to_string(key), else: key

      with true <- is_binary(key),
           {:ok, _, budget} <- normalize(key, budget - 2, depth + 1),
           {:ok, item, budget} <- normalize(item, budget, depth + 1) do
        {:cont, {:ok, Map.put(acc, key, item), budget}}
      else
        _ -> {:halt, :error}
      end
    end)
  end

  defp normalize(value, bytes, depth) when is_list(value) do
    value
    |> Enum.reduce_while({:ok, [], bytes - 2}, fn item, {:ok, acc, budget} ->
      case normalize(item, budget - 1, depth + 1) do
        {:ok, item, budget} -> {:cont, {:ok, [item | acc], budget}}
        _ -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, items, budget} -> {:ok, Enum.reverse(items), budget}
      other -> other
    end
  end

  defp normalize(value, bytes, _) when is_binary(value) and byte_size(value) > bytes, do: :error

  defp normalize(value, bytes, _) when is_binary(value) or is_number(value) or value in [nil, true, false] do
    budget = bytes - byte_size(JSON.encode!(value))
    if budget >= 0, do: {:ok, value, budget}, else: :error
  end

  defp normalize(value, bytes, depth) when is_atom(value), do: normalize(Atom.to_string(value), bytes, depth)
  defp normalize(_, _, _), do: :error
end
