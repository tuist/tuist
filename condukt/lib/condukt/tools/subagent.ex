defmodule Condukt.Tools.Subagent do
  @moduledoc """
  Tool for delegating a task to a registered sub-agent role.

  This tool is injected automatically when an agent declares `subagents/0`.
  It starts a fresh child `Condukt.Session`, runs the task once, returns the
  child's final response, and terminates the child session.
  """

  use Condukt.Tool

  alias Condukt.Operation.SubmitTool
  alias Condukt.Telemetry
  alias Condukt.TraceContext

  @contract_keys [:input, :input_schema, :output, :output_schema]
  @run_opt_keys [:timeout, :max_turns, :images]

  @impl true
  def name, do: "subagent"

  @impl true
  def name(_opts), do: name()

  @impl true
  def description do
    "Delegate a task to one of the registered sub-agent roles."
  end

  @impl true
  def description(_opts), do: description()

  @impl true
  def parameters(opts) do
    subagents = Keyword.get(opts, :subagents, [])

    role_schemas = Enum.map(subagents, &role_parameter_schema/1)

    if role_schemas == [] do
      fallback_parameters(opts)
    else
      %{
        type: "object",
        oneOf: role_schemas
      }
    end
  end

  defp role_parameter_schema({role, registration}) do
    input_schema = registration_input_schema(registration)

    properties =
      %{
        role: %{
          type: "string",
          enum: [Atom.to_string(role)],
          description: "Registered sub-agent role to run."
        },
        task: %{
          type: "string",
          description: "What the sub-agent should do."
        }
      }
      |> maybe_put_input_schema(input_schema)

    required =
      ["role", "task"]
      |> maybe_require_input(input_schema)

    %{
      type: "object",
      properties: properties,
      required: required
    }
  end

  defp registration_input_schema(module) when is_atom(module), do: nil

  defp registration_input_schema({_module, opts}) when is_list(opts) do
    Keyword.get(opts, :input) || Keyword.get(opts, :input_schema)
  end

  defp registration_input_schema(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      Keyword.get(opts, :input) || Keyword.get(opts, :input_schema)
    end
  end

  defp maybe_put_input_schema(properties, nil), do: properties
  defp maybe_put_input_schema(properties, schema), do: Map.put(properties, :input, schema)

  defp maybe_require_input(required, nil), do: required

  defp maybe_require_input(required, schema) do
    if input_required?(schema), do: required ++ ["input"], else: required
  end

  defp input_required?(schema) do
    schema
    |> schema_required()
    |> Enum.any?()
  end

  defp schema_required(schema) do
    Map.get(schema, :required) || Map.get(schema, "required") || []
  end

  defp fallback_parameters(opts) do
    roles =
      opts
      |> Keyword.get(:subagents, [])
      |> Enum.map(fn {role, _registration} -> Atom.to_string(role) end)

    %{
      type: "object",
      properties: %{
        role: %{
          type: "string",
          enum: roles,
          description: "Registered sub-agent role to run."
        },
        task: %{
          type: "string",
          description: "What the sub-agent should do."
        }
      },
      required: ["role", "task"]
    }
  end

  @impl true
  def call(args, context) do
    role = Map.get(args, "role") || Map.get(args, :role)
    task = Map.get(args, "task") || Map.get(args, :task)

    with {:ok, registered_role, registration} <- lookup(context, role) do
      call_registered(args, context, registered_role, task, registration)
    end
  end

  defp call_registered(args, context, role, task, registration) do
    base_metadata = subagent_metadata(context, role, registration)

    {result, _child_session_id} =
      Telemetry.span(
        :subagent,
        base_metadata,
        fn ->
          with {:ok, input} <- validate_input(args, registration.input_schema),
               {:ok, supervisor} <- fetch_supervisor(context),
               prepared = prepare_child(registration, context),
               {:ok, child} <- start_child(supervisor, registration.agent_module, prepared.session_opts) do
            child_id = safe_session_id(child)
            {run_and_stop(supervisor, child, task, input, prepared), child_id}
          else
            error -> {error, nil}
          end
        end,
        fn {result, child_session_id} ->
          subagent_stop_metadata(result, maybe_put(base_metadata, :session_id, child_session_id))
        end
      )

    result
  end

  defp subagent_metadata(context, role, registration) do
    %{
      agent: Map.get(context, :agent_module, Map.get(context, :agent)),
      parent_session_id: Map.get(context, :session_id),
      role: role,
      child_agent: registration.agent_module,
      input?: not is_nil(registration.input_schema),
      output?: not is_nil(registration.output_schema)
    }
  end

  defp safe_session_id(pid) when is_pid(pid) do
    if Process.alive?(pid), do: Condukt.Session.id(pid)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp subagent_stop_metadata({:ok, _result}, metadata), do: Map.put(metadata, :status, :ok)

  defp subagent_stop_metadata({:error, reason}, metadata) do
    metadata
    |> Map.put(:status, :error)
    |> Map.put(:error, error_name(reason))
  end

  defp error_name({:invalid_input, _error}), do: :invalid_input
  defp error_name({:invalid_output, _error}), do: :invalid_output
  defp error_name({:invalid_subagent_registration, _registration}), do: :invalid_subagent_registration
  defp error_name(reason) when is_atom(reason), do: reason
  defp error_name(reason) when is_binary(reason), do: :error
  defp error_name(_reason), do: :error

  defp lookup(context, role) when is_binary(role) do
    context
    |> subagents()
    |> Enum.find(fn {registered_role, _registration} -> Atom.to_string(registered_role) == role end)
    |> case do
      nil ->
        {:error, "no sub-agent registered as #{role}"}

      {registered_role, registration} ->
        with {:ok, registration} <- normalize_registration(registration) do
          {:ok, registered_role, registration}
        end
    end
  end

  defp lookup(_context, role), do: {:error, "no sub-agent registered as #{inspect(role)}"}

  defp normalize_registration(module) when is_atom(module) do
    {:ok, %{agent_module: module, opts: [], input_schema: nil, output_schema: nil}}
  end

  defp normalize_registration({module, opts}) when is_atom(module) and is_list(opts) do
    {:ok,
     %{
       agent_module: module,
       opts: Keyword.drop(opts, @contract_keys),
       input_schema: Keyword.get(opts, :input) || Keyword.get(opts, :input_schema),
       output_schema: Keyword.get(opts, :output) || Keyword.get(opts, :output_schema)
     }}
  end

  defp normalize_registration(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      {:ok,
       %{
         agent_module: Condukt.AnonymousAgent,
         opts:
           opts
           |> Keyword.drop(@contract_keys)
           |> Keyword.put_new(:load_project_instructions, false),
         input_schema: Keyword.get(opts, :input) || Keyword.get(opts, :input_schema),
         output_schema: Keyword.get(opts, :output) || Keyword.get(opts, :output_schema)
       }}
    else
      {:error, {:invalid_subagent_registration, opts}}
    end
  end

  defp normalize_registration(registration), do: {:error, {:invalid_subagent_registration, registration}}

  defp subagents(context) do
    context
    |> Map.get(:opts, [])
    |> Keyword.get(:subagents, Map.get(context, :subagents, []))
  end

  defp fetch_supervisor(%{subagent_supervisor: supervisor}) when is_pid(supervisor), do: {:ok, supervisor}
  defp fetch_supervisor(_context), do: {:error, :subagent_supervisor_unavailable}

  defp validate_input(args, nil) do
    case fetch_input(args) do
      {:ok, input} -> {:ok, stringify_keys(input)}
      :error -> {:ok, nil}
    end
  end

  defp validate_input(args, schema) do
    input =
      case fetch_input(args) do
        {:ok, input} -> stringify_keys(input)
        :error -> default_input(schema)
      end

    with {:ok, root} <- JSV.build(schema),
         {:ok, validated} <- JSV.validate(input, root) do
      {:ok, validated}
    else
      {:error, error} -> {:error, {:invalid_input, error}}
    end
  end

  defp fetch_input(args) do
    cond do
      Map.has_key?(args, "input") -> {:ok, Map.fetch!(args, "input")}
      Map.has_key?(args, :input) -> {:ok, Map.fetch!(args, :input)}
      true -> :error
    end
  end

  defp default_input(schema) do
    case Map.get(schema, :type) || Map.get(schema, "type") do
      "array" -> []
      _type -> %{}
    end
  end

  defp prepare_child(registration, context) do
    {run_opts, session_opts} = Keyword.split(registration.opts, @run_opt_keys)

    prepared = %{
      session_opts: inherit(session_opts, context),
      run_opts: run_opts,
      output_schema: registration.output_schema,
      trace_context: Map.get(context, :trace_context) || TraceContext.current(),
      ref: nil
    }

    maybe_prepare_structured_output(prepared, registration.agent_module)
  end

  defp maybe_prepare_structured_output(%{output_schema: nil} = prepared, _agent_module), do: prepared

  defp maybe_prepare_structured_output(prepared, agent_module) do
    ref = make_ref()
    submit_tool = {SubmitTool, schema: prepared.output_schema, reply_to: self(), ref: ref}

    session_opts =
      prepared.session_opts
      |> append_submit_tool(agent_module, submit_tool)
      |> put_structured_system_prompt(agent_module)

    %{prepared | session_opts: session_opts, ref: ref}
  end

  defp append_submit_tool(session_opts, agent_module, submit_tool) do
    tools = Keyword.get_lazy(session_opts, :tools, fn -> agent_module.tools() end)
    Keyword.put(session_opts, :tools, tools ++ [submit_tool])
  end

  defp put_structured_system_prompt(session_opts, agent_module) do
    base_system = Keyword.get_lazy(session_opts, :system_prompt, fn -> agent_system_prompt(agent_module) end)

    Keyword.put(
      session_opts,
      :system_prompt,
      compose_system_prompt(
        base_system,
        "When you have your final answer, call the `submit_result` tool. Call it exactly once, then stop."
      )
    )
  end

  defp agent_system_prompt(agent_module) do
    if function_exported?(agent_module, :system_prompt, 0) do
      agent_module.system_prompt()
    end
  end

  defp compose_system_prompt(nil, addition), do: addition

  defp compose_system_prompt(base, addition) do
    [base, addition]
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp inherit(opts, context) do
    opts
    |> Keyword.put_new(:sandbox, Map.fetch!(context, :sandbox))
    |> Keyword.put_new(:cwd, Map.fetch!(context, :cwd))
    |> put_new_present(:secrets, Map.get(context, :secrets))
    |> put_new_present(:model, Map.get(context, :model))
    |> put_new_present(:thinking_level, Map.get(context, :thinking_level))
    |> put_new_present(:max_tokens, Map.get(context, :max_tokens))
    |> put_new_present(:api_key, Map.get(context, :api_key))
    |> put_new_present(:base_url, Map.get(context, :base_url))
    |> put_new_present(:llm_request_options, Map.get(context, :llm_request_options))
  end

  defp put_new_present(opts, _key, nil), do: opts
  defp put_new_present(opts, key, value), do: Keyword.put_new(opts, key, value)

  defp start_child(supervisor, agent_module, opts) do
    child_spec = %{
      id: {__MODULE__, make_ref()},
      start: {Condukt.Session, :start_link, [agent_module, opts]},
      restart: :temporary,
      type: :worker
    }

    case DynamicSupervisor.start_child(supervisor, child_spec) do
      {:ok, pid} -> {:ok, pid}
      {:ok, pid, _info} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_and_stop(supervisor, child, task, input, prepared) do
    result = run_child(child, child_prompt(task, input), prepared.run_opts, prepared.trace_context)

    terminate_child(supervisor, child)

    case {result, prepared.output_schema} do
      {{:ok, _text}, nil} -> result
      {{:ok, _text}, output_schema} -> await_submission(output_schema, prepared.ref)
      {result, _output_schema} -> result
    end
  end

  defp run_child(child, prompt, run_opts, trace_context) do
    caller = self()
    ref = make_ref()

    pid =
      spawn(fn ->
        TraceContext.attach(trace_context)
        send(caller, {ref, Condukt.run(child, prompt, run_opts)})
      end)

    monitor_ref = Process.monitor(pid)

    receive do
      {^ref, result} ->
        Process.demonitor(monitor_ref, [:flush])
        result

      {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
        {:error, reason}
    end
  end

  defp child_prompt(task, nil), do: task

  defp child_prompt(task, input) do
    "Run this task:\n\n#{task}\n\nStructured input:\n\n```json\n#{JSON.encode!(input)}\n```"
  end

  defp await_submission(output_schema, ref) do
    receive do
      {^ref, :operation_submit, submitted} ->
        validate_output(output_schema, submitted)
    after
      0 -> {:error, :no_result_submitted}
    end
  end

  defp validate_output(schema, data) do
    with {:ok, root} <- JSV.build(schema),
         {:ok, validated} <- JSV.validate(data, root) do
      {:ok, atomize_top_level(validated, schema)}
    else
      {:error, error} -> {:error, {:invalid_output, error}}
    end
  end

  defp atomize_top_level(map, schema) when is_map(map) do
    properties = Map.get(schema, :properties) || Map.get(schema, "properties") || %{}

    if properties != %{} and Enum.all?(properties, fn {key, _schema} -> is_atom(key) end) do
      name_map = Map.new(properties, fn {atom_key, _schema} -> {Atom.to_string(atom_key), atom_key} end)
      Map.new(map, &remap_key(&1, name_map))
    else
      map
    end
  end

  defp atomize_top_level(other, _schema), do: other

  defp remap_key({key, value}, name_map) when is_binary(key) do
    case Map.fetch(name_map, key) do
      {:ok, atom_key} -> {atom_key, value}
      :error -> {key, value}
    end
  end

  defp remap_key(kv, _name_map), do: kv

  defp stringify_keys(map) when is_map(map) and not is_struct(map) do
    Map.new(map, fn {key, value} -> {to_string_key(key), stringify_keys(value)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(other), do: other

  defp to_string_key(key) when is_atom(key), do: Atom.to_string(key)
  defp to_string_key(key) when is_binary(key), do: key

  defp terminate_child(supervisor, child) do
    if Process.alive?(child) do
      _ = DynamicSupervisor.terminate_child(supervisor, child)
    end

    :ok
  end
end
