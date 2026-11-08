defmodule Condukt.AnonymousRun do
  @moduledoc false
  #
  # Implementation backing `Condukt.run/2` when called with a prompt as the
  # first argument (no agent module required).
  #
  # Three modes, dispatched on the presence of `:input` and `:output`:
  #
  # * neither — free-form chat, returns `{:ok, text}`
  # * `:input` only — prompt becomes instructions, args become the user
  #   message, returns `{:ok, text}`
  # * `:output` (with or without `:input`) — structured mode: the synthetic
  #   `submit_result` tool is appended, output is validated with JSV, and the
  #   call returns `{:ok, validated_map}`
  #
  # The runtime spins up a transient `Condukt.Session` against
  # `Condukt.AnonymousAgent`, runs the loop, and tears it down.

  alias Condukt.AnonymousAgent
  alias Condukt.Operation.SubmitTool
  alias Condukt.Session
  alias Condukt.SessionID
  alias Condukt.Telemetry

  @run_opt_keys [:timeout, :max_turns, :images, :trace_context]
  @runtime_keys [:input, :output, :input_schema]

  def run(prompt, opts) when is_binary(prompt) and is_list(opts) do
    opts = Keyword.put_new_lazy(opts, :id, &SessionID.generate/0)

    Telemetry.span(:run, run_metadata(opts), fn ->
      do_run(prompt, opts, AnonymousAgent, false)
    end)
  end

  def run(agent_module, prompt, opts) when is_atom(agent_module) and is_binary(prompt) and is_list(opts) do
    opts =
      opts
      |> Keyword.put_new(:tools, agent_module.tools())
      |> Keyword.put_new_lazy(:id, &SessionID.generate/0)

    Telemetry.span(:run, run_metadata(opts), fn ->
      do_run(prompt, opts, agent_module, true)
    end)
  end

  defp run_metadata(opts) do
    %{
      structured?: not is_nil(Keyword.get(opts, :output)),
      input?: not is_nil(Keyword.get(opts, :input)),
      session_id: Keyword.get(opts, :id)
    }
  end

  defp do_run(prompt, opts, agent_module, load_project_instructions) do
    output_schema = Keyword.get(opts, :output)
    input_args = Keyword.get(opts, :input)
    input_schema = Keyword.get(opts, :input_schema)

    cond do
      not is_nil(output_schema) ->
        run_structured(prompt, input_args, input_schema, output_schema, opts, agent_module, load_project_instructions)

      not is_nil(input_args) ->
        run_freeform_with_input(prompt, input_args, input_schema, opts, agent_module, load_project_instructions)

      true ->
        run_freeform(prompt, opts, agent_module, load_project_instructions)
    end
  end

  defp run_freeform(prompt, opts, agent_module, load_project_instructions) do
    {session_opts, run_opts} = split_opts(opts)
    session_opts = put_load_project_instructions_default(session_opts, load_project_instructions)

    with_session(agent_module, session_opts, fn pid ->
      Session.run(pid, prompt, run_opts)
    end)
  end

  defp run_freeform_with_input(prompt, input, input_schema, opts, agent_module, load_project_instructions) do
    with :ok <- validate_input(input, input_schema) do
      base_system = Keyword.get(opts, :system_prompt)
      system_prompt = compose_system(base_system, prompt, nil)
      user_message = encode_args(input)

      {session_opts, run_opts} = split_opts(opts)

      session_opts =
        session_opts
        |> Keyword.put(:system_prompt, system_prompt)
        |> put_load_project_instructions_default(load_project_instructions)

      with_session(agent_module, session_opts, fn pid ->
        Session.run(pid, user_message, run_opts)
      end)
    end
  end

  defp run_structured(prompt, input, input_schema, output_schema, opts, agent_module, load_project_instructions) do
    with :ok <- validate_input(input, input_schema) do
      do_run_structured(prompt, input, output_schema, opts, agent_module, load_project_instructions)
    end
  end

  defp do_run_structured(prompt, input, output_schema, opts, agent_module, load_project_instructions) do
    ref = make_ref()
    submit_tool = {SubmitTool, schema: output_schema, reply_to: self(), ref: ref}
    user_message = structured_user_message(input)
    {session_opts, run_opts} = split_opts(opts)

    session_opts =
      opts
      |> structured_session_opts(prompt, submit_tool, session_opts)
      |> put_load_project_instructions_default(load_project_instructions)

    with_session(agent_module, session_opts, fn pid ->
      complete_structured_run(pid, user_message, run_opts, output_schema, ref)
    end)
  end

  defp structured_session_opts(opts, prompt, submit_tool, session_opts) do
    base_tools = Keyword.get(opts, :tools, [])
    base_system = Keyword.get(opts, :system_prompt)

    session_opts
    |> Keyword.put(:tools, base_tools ++ [submit_tool])
    |> Keyword.put(:system_prompt, compose_system(base_system, prompt, :submit))
  end

  defp structured_user_message(nil) do
    "Provide your final answer by calling the submit_result tool."
  end

  defp structured_user_message(input) when is_map(input), do: encode_args(input)

  defp complete_structured_run(pid, user_message, run_opts, output_schema, ref) do
    case Session.run(pid, user_message, run_opts) do
      {:ok, _text} -> await_submission(output_schema, ref)
      {:error, reason} -> {:error, reason}
    end
  end

  defp split_opts(opts) do
    {run_opts, rest} = Keyword.split(opts, @run_opt_keys)
    session_opts = Keyword.drop(rest, @runtime_keys)
    {session_opts, run_opts}
  end

  defp put_load_project_instructions_default(session_opts, value) do
    Keyword.put_new(session_opts, :load_project_instructions, value)
  end

  defp with_session(agent_module, session_opts, fun) do
    Session.with_transient(agent_module, session_opts, fun)
  end

  defp encode_args(args) do
    "Run with these arguments:\n\n```json\n#{JSON.encode!(args)}\n```"
  end

  defp compose_system(base, instructions, mode) do
    submit_note =
      if mode == :submit do
        "When you have your final answer, call the `submit_result` tool. Call it exactly once, then stop."
      end

    [base, instructions, submit_note]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> nil
      pieces -> Enum.join(pieces, "\n\n")
    end
  end

  defp validate_input(nil, nil), do: :ok
  defp validate_input(args, nil) when is_map(args), do: :ok
  defp validate_input(_args, nil), do: {:error, {:invalid_input, :input_must_be_a_map}}

  defp validate_input(args, schema) when is_map(args) do
    case JSV.build(schema) do
      {:ok, root} ->
        case JSV.validate(stringify_keys(args), root) do
          {:ok, _} -> :ok
          {:error, error} -> {:error, {:invalid_input, error}}
        end

      {:error, error} ->
        {:error, {:invalid_input_schema, error}}
    end
  end

  defp validate_input(_args, _schema) do
    {:error, {:invalid_input, :input_must_be_a_map}}
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
    case JSV.build(schema) do
      {:ok, root} ->
        case JSV.validate(data, root) do
          {:ok, validated} -> {:ok, atomize_top_level(validated, schema)}
          {:error, error} -> {:error, {:invalid_output, error}}
        end

      {:error, error} ->
        {:error, {:invalid_output_schema, error}}
    end
  end

  defp atomize_top_level(map, schema) when is_map(map) do
    properties = Map.get(schema, :properties) || Map.get(schema, "properties") || %{}

    if properties != %{} and Enum.all?(properties, fn {k, _} -> is_atom(k) end) do
      name_map = Map.new(properties, fn {atom_key, _} -> {Atom.to_string(atom_key), atom_key} end)
      Map.new(map, &remap_key(&1, name_map))
    else
      map
    end
  end

  defp atomize_top_level(other, _schema), do: other

  defp remap_key({k, v}, name_map) when is_binary(k) do
    case Map.fetch(name_map, k) do
      {:ok, atom_key} -> {atom_key, v}
      :error -> {k, v}
    end
  end

  defp remap_key(kv, _name_map), do: kv

  defp stringify_keys(map) when is_map(map) and not is_struct(map) do
    Map.new(map, fn {k, v} -> {to_string_key(k), stringify_keys(v)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(other), do: other

  defp to_string_key(k) when is_atom(k), do: Atom.to_string(k)
  defp to_string_key(k) when is_binary(k), do: k
end
