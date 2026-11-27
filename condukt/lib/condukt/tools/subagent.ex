defmodule Condukt.Tools.Subagent do
  @moduledoc """
  Tool for delegating a task to a registered sub-agent role.

  This tool is injected automatically when an agent declares `subagents/0`.
  It starts a fresh child `Condukt.Session`, runs the task once, returns the
  child's final response, and terminates the child session.

  The child belongs to the call: it runs under a supervisor linked to the
  call's process, so when the parent's turn is aborted and the call goes down,
  the supervisor shuts the child down, and the child's own turn with it. While
  the parent streams, the child streams too, and its events reach the parent's
  stream as `{:subagent, tool_call_id, event}`.

  Roles registered with `background: true` are served by
  `Condukt.Tools.BackgroundSubagent` instead.
  """

  use Condukt.Tool

  alias Condukt.Message
  alias Condukt.Operation.SubmitTool
  alias Condukt.Sandbox
  alias Condukt.Session
  alias Condukt.Telemetry
  alias Condukt.Tools.BackgroundSubagent
  alias Condukt.TraceContext

  @contract_keys [:input, :input_schema, :output, :output_schema, :background]
  @run_opt_keys [:timeout, :max_turns, :images]
  @default_timeout 300_000

  @doc false
  # The tools a session with these normalized registrations gets: this one for
  # one-shot roles, and the background tool, with its manager started under
  # `supervisor`, for roles registered with `background: true`.
  def tools([], _supervisor), do: []

  def tools(subagents, supervisor) do
    {background, foreground} = Enum.split_with(subagents, &background?/1)

    foreground_tools = if foreground == [], do: [], else: [{__MODULE__, subagents: foreground}]
    foreground_tools ++ BackgroundSubagent.tools(background, supervisor)
  end

  defp background?({_role, {_module, opts}}), do: Keyword.get(opts, :background, false) == true

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
          case validate_input(args, registration.input_schema) do
            {:ok, input} ->
              prepared = prepare_child(registration, context, self())
              run_owned(registration.agent_module, task, input, prepared, context)

            error ->
              {error, nil}
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

  @doc false
  def lookup(context, role) when is_binary(role) do
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

  def lookup(_context, role), do: {:error, "no sub-agent registered as #{inspect(role)}"}

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

  @doc false
  # Whether a call to the role in `args` changes nothing a later call could
  # observe, so consecutive such calls run together: the role starts a
  # sandbox of its own, from a spec, or has only read-only tools and no
  # sub-agents of its own. A role that shares its parent's sandbox and can
  # change it runs alone, in call order.
  def read_only_call?(opts, args) do
    role = Map.get(args, "role") || Map.get(args, :role)

    case lookup(%{opts: opts}, role) do
      {:ok, _role, %{agent_module: module, opts: role_opts}} ->
        own_sandbox?(role_opts) or
          (Code.ensure_loaded?(module) and module.subagents() == [] and
             Enum.all?(Keyword.get_lazy(role_opts, :tools, &module.tools/0), &Condukt.Tool.read_only?/1))

      # It only answers with an error.
      {:error, _reason} ->
        true
    end
  end

  defp own_sandbox?(role_opts) do
    case Keyword.get(role_opts, :sandbox) do
      nil -> false
      %Sandbox{} -> false
      _spec -> true
    end
  end

  defp subagents(context) do
    context
    |> Map.get(:opts, [])
    |> Keyword.get(:subagents, Map.get(context, :subagents, []))
  end

  @doc false
  def validate_input(args, nil) do
    case fetch_input(args) do
      {:ok, input} -> {:ok, stringify_keys(input)}
      :error -> {:ok, nil}
    end
  end

  def validate_input(args, schema) do
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

  @doc false
  # `reply_to` receives the child's structured submissions.
  def prepare_child(registration, context, reply_to) do
    {run_opts, session_opts} = Keyword.split(registration.opts, @run_opt_keys)

    prepared = %{
      session_opts: inherit(session_opts, context),
      run_opts: run_opts,
      output_schema: registration.output_schema,
      trace_context: Map.get(context, :trace_context) || TraceContext.current(),
      ref: nil
    }

    maybe_prepare_structured_output(prepared, registration.agent_module, reply_to)
  end

  defp maybe_prepare_structured_output(%{output_schema: nil} = prepared, _agent_module, _reply_to), do: prepared

  defp maybe_prepare_structured_output(prepared, agent_module, reply_to) do
    ref = make_ref()
    submit_tool = {SubmitTool, schema: prepared.output_schema, reply_to: reply_to, ref: ref}

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
    |> put_new_present(:parent, Map.get(context, :session_id))
    |> put_new_present(:secrets, Map.get(context, :secrets))
    |> put_new_present(:model, Map.get(context, :model))
    |> put_new_present(:thinking_level, Map.get(context, :thinking_level))
    |> put_new_present(:max_tokens, Map.get(context, :max_tokens))
    |> put_new_present(:api_key, Map.get(context, :api_key))
    |> put_new_present(:base_url, Map.get(context, :base_url))
    |> put_new_present(:llm_request_options, Map.get(context, :llm_request_options))
    |> put_new_present(:image_policy, Map.get(context, :image_policy))
  end

  defp put_new_present(opts, _key, nil), do: opts
  defp put_new_present(opts, key, value), do: Keyword.put_new(opts, key, value)

  @doc false
  def start_child(supervisor, agent_module, opts) do
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

  # The child runs under a supervisor this call starts linked to itself, the
  # call's own branch of the parent's process tree. When the parent's turn is
  # aborted, the call goes down, and the supervisor, hearing its parent exit,
  # shuts the child down. A child that crashes takes only itself down, and the
  # call reports it as an error. Stopping the supervisor at the end of the call
  # stops the child, so it never outlives the call.
  defp run_owned(agent_module, task, input, prepared, context) do
    {:ok, supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)

    try do
      case start_child(supervisor, agent_module, prepared.session_opts) do
        {:ok, child} ->
          child_id = safe_session_id(child)
          {run_child_task(child, task, input, prepared, context), child_id}

        error ->
          {error, nil}
      end
    after
      Supervisor.stop(supervisor)
    end
  end

  defp run_child_task(child, task, input, prepared, context) do
    prompt = child_prompt(task, input)

    result =
      if Map.get(context, :stream?, false),
        do: stream_child(child, prompt, prepared, context),
        else: run_child(child, prompt, prepared)

    case {result, prepared.output_schema} do
      {{:ok, _text}, nil} -> result
      {{:ok, _text}, output_schema} -> await_submission(output_schema, prepared.ref)
      {result, _output_schema} -> result
    end
  catch
    :exit, reason -> {:error, {:session_exit, reason}}
  end

  defp run_child(child, prompt, prepared) do
    opts = Keyword.put(prepared.run_opts, :trace_context, prepared.trace_context)
    Condukt.run(child, prompt, opts)
  end

  # Streams the child's turn into the parent's, collecting the same final
  # answer `Condukt.run/3` would return.
  defp stream_child(child, prompt, prepared, context) do
    ref = make_ref()
    monitor = Process.monitor(child)
    deadline = System.monotonic_time(:millisecond) + (prepared.run_opts[:timeout] || @default_timeout)

    opts =
      prepared.run_opts
      |> Keyword.take([:max_turns, :images])
      |> Keyword.put(:trace_context, prepared.trace_context)

    :ok = Session.stream_to(child, prompt, opts, ref)

    case await_stream(child, ref, monitor, deadline, forwarder(context), nil) do
      # A runtime without streaming did not run anything, so run it instead.
      {:error, {:streaming_not_supported_by_runtime, _runtime}} ->
        Process.demonitor(monitor, [:flush])
        run_child(child, prompt, prepared)

      result ->
        Process.demonitor(monitor, [:flush])
        result
    end
  end

  defp await_stream(child, ref, monitor, deadline, forward, error) do
    receive do
      {^ref, :done} when not is_nil(error) ->
        if !match?({:streaming_not_supported_by_runtime, _}, error), do: forward.(:done)
        {:error, error}

      {^ref, :done} ->
        forward.(:done)
        {:ok, final_text(child)}

      {^ref, {:error, {:streaming_not_supported_by_runtime, _} = reason}} ->
        await_stream(child, ref, monitor, deadline, forward, error || reason)

      {^ref, {:error, reason} = event} ->
        forward.(event)
        await_stream(child, ref, monitor, deadline, forward, error || reason)

      {^ref, event} ->
        forward.(event)
        await_stream(child, ref, monitor, deadline, forward, error)

      {:DOWN, ^monitor, :process, ^child, reason} ->
        {:error, {:session_exit, reason}}
    after
      # Stopping the call's supervisor stops the child.
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        {:error, {:session_exit, :timeout}}
    end
  end

  defp forwarder(context) do
    parent = Map.fetch!(context, :agent)
    turn_ref = Map.get(context, :turn_ref)
    call_id = Map.get(context, :tool_call_id)
    fn event -> Session.forward_event(parent, turn_ref, {:subagent, call_id, event}) end
  end

  # The text of the child's last assistant message, as `Condukt.run/3` returns.
  defp final_text(child) do
    child
    |> Condukt.history()
    |> Enum.reverse()
    |> Enum.find(&(&1.role == :assistant))
    |> case do
      nil -> ""
      message -> Message.text(message)
    end
  end

  @doc false
  def child_prompt(task, nil), do: task

  def child_prompt(task, input) do
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

  @doc false
  def validate_output(schema, data) do
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
end
