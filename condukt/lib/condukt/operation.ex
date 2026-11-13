defmodule Condukt.Operation do
  @moduledoc """
  Typed, named entrypoints on an agent module.

  An operation declares an input schema, an output schema, and a block of
  instructions. The macro generates a function on the agent module that
  validates the input, runs the operation through Condukt's structured
  anonymous run path, validates the output, and returns it.

  ## Declaring

      defmodule MyApp.ReviewAgent do
        use Condukt

        @impl true
        def tools, do: [Condukt.Tools.Read]

        operation :review_pr,
          input: %{
            type: "object",
            properties: %{
              repo: %{type: "string"},
              pr_number: %{type: "integer"}
            },
            required: ["repo", "pr_number"]
          },
          output: %{
            type: "object",
            properties: %{
              verdict: %{type: "string", enum: ["approve", "request_changes", "comment"]},
              summary: %{type: "string"}
            },
            required: ["verdict", "summary"]
          },
          instructions: \"""
          Read the PR, decide a verdict, and write a summary.
          \"""
      end

  ## Calling

      {:ok, %{verdict: "approve", summary: _}} =
        MyApp.ReviewAgent.review_pr(%{repo: "tuist/condukt", pr_number: 1})

  Each call runs without keeping history across calls.

  Schemas must be JSON Schema maps. Atom keys are accepted in both schemas
  and call-site arguments — they are normalized internally.
  """

  alias Condukt.Telemetry

  defstruct [:name, :input_schema, :output_schema, :instructions]

  @doc false
  defmacro operation(name, opts) do
    input_ast = Keyword.fetch!(opts, :input)
    output_ast = Keyword.fetch!(opts, :output)
    instructions_ast = Keyword.fetch!(opts, :instructions)

    quote do
      @condukt_operations {unquote(name), unquote(input_ast), unquote(output_ast), unquote(instructions_ast)}

      def unquote(name)(args, run_opts \\ []) do
        Condukt.Operation.run(__MODULE__, unquote(name), args, run_opts)
      end
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    ops = Module.get_attribute(env.module, :condukt_operations) || []

    ops_map =
      Map.new(ops, fn {name, input, output, instructions} ->
        {name,
         %__MODULE__{
           name: name,
           input_schema: input,
           output_schema: output,
           instructions: instructions
         }}
      end)

    if ops_map == %{} do
      quote do
        @doc false
        def __operations__, do: %{}

        @doc false
        def __operation__(_name), do: :error
      end
    else
      quote do
        @doc false
        def __operations__, do: unquote(Macro.escape(ops_map))

        @doc false
        def __operation__(name), do: Map.fetch(__operations__(), name)
      end
    end
  end

  @doc """
  Runs an operation declared on `agent_module`.

  Returns `{:ok, result}` on success or `{:error, reason}` on failure.
  Failure reasons:

  - `{:invalid_input, %JSV.ValidationError{}}` — args did not match the input schema
  - `{:invalid_output, %JSV.ValidationError{}}` — model output did not match the output schema
  - `:no_result_submitted` — the agent finished without calling `submit_result`
  - `{:unknown_operation, name}` — no operation by that name on the module
  - any error returned by the underlying `Condukt.Session.run/3`
  """
  def run(agent_module, name, args, opts \\ []) do
    opts = Keyword.put_new_lazy(opts, :id, &Condukt.SessionID.generate/0)
    metadata = %{agent: agent_module, operation: name, session_id: Keyword.fetch!(opts, :id)}

    Telemetry.span(:operation, metadata, fn ->
      with {:ok, operation} <- fetch_operation(agent_module, name),
           {:ok, normalized} <- normalize(args) do
        execute(agent_module, operation, normalized, opts)
      end
    end)
  end

  defp fetch_operation(agent_module, name) do
    case agent_module.__operation__(name) do
      {:ok, operation} -> {:ok, operation}
      :error -> {:error, {:unknown_operation, name}}
    end
  end

  defp normalize(args) when is_map(args) do
    {:ok, stringify_keys(args)}
  end

  defp normalize(_args) do
    {:error, {:invalid_input, :args_must_be_a_map}}
  end

  defp stringify_keys(map) when is_map(map) and not is_struct(map) do
    Map.new(map, fn {k, v} -> {to_string_key(k), stringify_keys(v)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(other), do: other

  defp to_string_key(k) when is_atom(k), do: Atom.to_string(k)
  defp to_string_key(k) when is_binary(k), do: k

  defp execute(agent_module, operation, args, opts) do
    base_prompt = base_system_prompt(agent_module)

    Condukt.AnonymousRun.run(
      agent_module,
      operation.instructions,
      anonymous_run_opts(agent_module, operation, args, base_prompt, opts)
    )
  end

  defp base_system_prompt(agent_module) do
    if function_exported?(agent_module, :system_prompt, 0) do
      agent_module.system_prompt() || ""
    else
      ""
    end
  end

  defp anonymous_run_opts(agent_module, operation, args, base_prompt, opts) do
    [
      input: args,
      input_schema: operation.input_schema,
      output: operation.output_schema,
      tools: agent_module.tools(),
      system_prompt: base_prompt,
      load_project_instructions: false
    ]
    |> maybe_put(:api_key, opts[:api_key])
    |> maybe_put(:base_url, opts[:base_url])
    |> maybe_put(:model, opts[:model])
    |> maybe_put(:id, opts[:id])
    |> maybe_put(:llm_request_options, opts[:llm_request_options])
    |> Keyword.merge(Keyword.take(opts, [:timeout, :max_turns, :trace_context]))
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
