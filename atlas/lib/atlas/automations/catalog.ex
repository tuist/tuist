defmodule Atlas.Automations.Catalog do
  @moduledoc "Trusted versioned behavior types. JS computes data; domain capabilities are explicitly registered."

  alias Atlas.Automations.Behavior
  alias Atlas.Automations.Contract
  alias Atlas.Automations.DomainRegistry
  alias Atlas.Automations.DomainRuntime
  alias Atlas.Automations.JavaScript
  alias Atlas.Tasks

  @object %{"type" => "object"}
  @task_input %{
    "type" => "object",
    "required" => ["title"],
    "additionalProperties" => false,
    "properties" => %{
      "title" => %{"type" => "string", "minLength" => 1, "maxLength" => 255},
      "description" => %{"type" => "string", "maxLength" => 2000}
    }
  }

  def types do
    (legacy_types() ++ DomainRegistry.types()) |> Enum.sort_by(&{&1.domain, &1.name, &1.version})
  end

  def valid_type?(name), do: not is_nil(legacy_type(name)) or match?({:ok, _}, DomainRegistry.fetch(name))

  def prepare_attributes(attrs, previous_type \\ nil) do
    reference = attrs["type"] || previous_type
    result = if is_nil(legacy_type(reference)), do: DomainRegistry.fetch(reference), else: :legacy

    case result do
      {:ok, entry} ->
        Enum.reduce(~w(input_schema output_schema), Map.put(attrs, "type", DomainRegistry.reference(entry)), fn key,
                                                                                                                acc ->
          if Map.get(acc, key, @object) == @object, do: Map.put(acc, key, entry[key]), else: acc
        end)

      _ ->
        attrs
    end
  end

  def snapshot(%Behavior{} = behavior) do
    case legacy_type(behavior.type) do
      nil ->
        domain_snapshot(behavior)

      type ->
        with :ok <- Contract.validate_schema(behavior.input_schema),
             :ok <- Contract.validate_schema(behavior.output_schema),
             :ok <- configuration(type.name, behavior.configuration),
             :ok <- effect_contract(%{behavior | type: type.name}) do
          {:ok,
           %{
             "type" => type.name,
             "version" => 1,
             "configuration" => behavior.configuration,
             "input_schema" => behavior.input_schema,
             "output_schema" => behavior.output_schema
           }}
        end
    end
  end

  def builtin(name) do
    case legacy_type(name) do
      %{name: "javascript.evaluate"} ->
        {:error, "JavaScript requires a saved source configuration."}

      nil ->
        with {:ok, entry} <- DomainRegistry.fetch(name), do: {:ok, DomainRegistry.snapshot(entry)}

      type ->
        {:ok,
         %{
           "type" => type.name,
           "version" => type.version,
           "configuration" => %{},
           "input_schema" => type.input_schema,
           "output_schema" => type.output_schema
         }}
    end
  end

  def execute(behavior, input, actor, opts \\ [])

  def execute(%{"type" => name, "version" => version} = behavior, input, actor, opts) do
    if version == 1 and not is_nil(legacy_type(name)) do
      with :ok <- Contract.validate(behavior["input_schema"], input),
           {:ok, output} <- perform(behavior, input, actor),
           :ok <- Contract.validate(behavior["output_schema"], output) do
        {:ok, output}
      end
    else
      with {:ok, entry} <- DomainRegistry.fetch(name, version),
           do: DomainRuntime.execute(entry, behavior, input, actor, opts)
    end
  end

  def execute(_, _, _, _), do: {:error, "Unsupported behavior version."}

  defp domain_snapshot(behavior) do
    with {:ok, entry} <- DomainRegistry.fetch(behavior.type),
         true <- behavior.configuration == %{},
         true <- behavior.input_schema in [@object, entry["input_schema"]],
         true <- behavior.output_schema in [@object, entry["output_schema"]] do
      {:ok, DomainRegistry.snapshot(entry)}
    else
      _ -> {:error, "Domain operations use their registered contract and empty configuration."}
    end
  end

  defp legacy_types do
    [
      %{
        name: "core.value",
        reference: "core.value",
        domain: "automation",
        description: "Return an object unchanged.",
        effect: "read",
        version: 1,
        permissions: [],
        requires_approval: false,
        execution_mode: "local_transaction",
        input_schema: @object,
        output_schema: @object
      },
      %{
        name: "tasks.create",
        reference: "tasks.create",
        domain: "tasks",
        description: "Legacy v1: create a task assigned to the execution user. Output: task_id and title.",
        effect: "write",
        version: 1,
        permissions: [],
        requires_approval: false,
        execution_mode: "local_transaction",
        input_schema: @task_input,
        output_schema: @object
      },
      %{
        name: "javascript.evaluate",
        reference: "javascript.evaluate",
        domain: "automation",
        description: "Compute an object using isolated JavaScript without host tools.",
        effect: "compute",
        version: 1,
        permissions: [],
        requires_approval: false,
        execution_mode: "isolated_compute",
        input_schema: @object,
        output_schema: @object
      }
    ]
  end

  defp legacy_type(name), do: Enum.find(legacy_types(), &(name in [&1.name, &1.name <> "@1"]))

  defp effect_contract(%Behavior{type: "tasks.create", output_schema: schema}) when schema != @object,
    do: {:error, "Task creation uses the built-in output contract."}

  defp effect_contract(_), do: :ok

  defp configuration("javascript.evaluate", %{"source" => source} = config) when is_binary(source) do
    if map_size(config) == 1 and byte_size(source) <= 65_536,
      do: :ok,
      else: {:error, "JavaScript configuration requires only a source of at most 64 KiB."}
  end

  defp configuration(type, config) when type in ["core.value", "tasks.create"] and config == %{}, do: :ok
  defp configuration(_, _), do: {:error, "Invalid behavior configuration."}

  defp perform(%{"type" => "core.value"}, input, _actor), do: {:ok, input}

  defp perform(%{"type" => "javascript.evaluate", "configuration" => %{"source" => source}}, input, _actor),
    do: JavaScript.evaluate(source, input)

  defp perform(%{"type" => "tasks.create"}, input, actor) do
    with :ok <- Contract.validate(@task_input, input),
         {:ok, task} <- Tasks.create_task(Map.put(input, "assignee_id", actor.id), actor, interface: "worker") do
      {:ok, %{"task_id" => task.id, "title" => task.title}}
    else
      _ -> {:error, "Could not create task."}
    end
  end
end
