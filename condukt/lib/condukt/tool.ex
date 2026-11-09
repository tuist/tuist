defmodule Condukt.Tool do
  @moduledoc """
  Behaviour for defining tools that agents can use.

  Tools are functions that agents can call to interact with the world:
  reading files, running commands, making HTTP requests, etc.

  ## Defining a Tool

      defmodule MyApp.Tools.Weather do
        use Condukt.Tool

        @impl true
        def name, do: "get_weather"

        @impl true
        def description do
          "Gets the current weather for a location"
        end

        @impl true
        def parameters do
          %{
            type: "object",
            properties: %{
              location: %{
                type: "string",
                description: "City name, e.g. 'San Francisco, CA'"
              }
            },
            required: ["location"]
          }
        end

        @impl true
        def call(%{"location" => location}, _context) do
          case WeatherAPI.get(location) do
            {:ok, data} -> {:ok, format_weather(data)}
            {:error, reason} -> {:error, reason}
          end
        end
      end

  ## Tool Context

  The `call/2` function receives a context map with:

  - `:agent` - The agent PID
  - `:agent_module` - The agent module for the session
  - `:sandbox` - The active `Condukt.Sandbox` struct (use this for any
    filesystem or process-execution work)
  - `:cwd` - Project working directory (kept for tools that need to refer to
    the host project root for non-sandbox concerns; tools that read/write
    files or run commands should go through `:sandbox`)
  - `:secrets` - Resolved session secrets. Built-in command tools expose these
    as environment variables. Custom trusted tools can use
    `Condukt.Secrets.env/1` when they need the same values.
  - `:opts` - Options passed when adding the tool to the agent
  - `:assigns` - A map of session-scoped assigns visible to every tool in
    the run. A tool can return `{:ok, result, %{key: value}}` to merge new
    entries into this map for the next turn.

  ## Sharing State Between Tools

  Use the third element of the success tuple to share facts across tool
  calls within a session, ExUnit-style:

      def call(args, ctx) do
        case ctx.assigns[:found_account_id] do
          nil ->
            {:ok, account} = lookup(args)
            {:ok, render(account), %{found_account_id: account.id}}

          id ->
            {:ok, render(get_account(id))}
        end
      end

  Returned maps are merged into the session's `:assigns` last-write-wins.
  Within a single batch of tool calls all tools see the same
  start-of-batch snapshot; updates take effect in the next turn.

  ## Sandbox-aware tools

  If your tool reads or writes files, or runs subprocesses, route through
  `Condukt.Sandbox.read/2`, `Condukt.Sandbox.write/3`, `Condukt.Sandbox.exec/3`,
  etc. Direct `File.*` or `MuonTrap.cmd/3` calls bypass the sandbox and break
  the consumer's ability to swap one in (e.g. an in-memory virtual sandbox).
  Tools that touch unrelated systems (HTTP APIs, databases, in-process state)
  have nothing to sandbox and are unaffected.

  ## Parameterized Tools

  Tools can be parameterized when added to an agent:

      defmodule MyApp.Tools.Database do
        use Condukt.Tool

        @impl true
        def name(opts), do: "query_\#{opts[:table]}"

        @impl true
        def description(opts) do
          "Query the \#{opts[:table]} table"
        end

        @impl true
        def call(args, context) do
          table = context.opts[:table]
          Repo.all(from r in table, where: ^build_where(args))
        end
      end

      # In agent:
      def tools do
        [
          {MyApp.Tools.Database, table: "users"},
          {MyApp.Tools.Database, table: "orders"}
        ]
      end
  """

  @doc """
  Returns the tool name as it will appear to the LLM.
  """
  @callback name() :: String.t()
  @callback name(opts :: keyword()) :: String.t()

  @doc """
  Returns a description of what the tool does.
  """
  @callback description() :: String.t()
  @callback description(opts :: keyword()) :: String.t()

  @doc """
  Returns the JSON Schema for the tool's parameters.
  """
  @callback parameters() :: map()
  @callback parameters(opts :: keyword()) :: map()

  @doc """
  Executes the tool with the given arguments.

  Tools may return:

    * `{:ok, result}` — the result is sent back to the LLM. Non-binary
      results are JSON-encoded automatically.
    * `{:ok, result, assigns}` — same as above, plus a map of values merged
      into the session's `:assigns`. Subsequent tool calls in the same run
      can read them as `context.assigns[:key]`. Last-write-wins on key
      collisions, matching `Phoenix.Component.assign/3`.
    * `{:error, reason}` — the LLM receives an error.

  Within a single batch of tool calls in one assistant message, each tool
  starts from the same start-of-batch `assigns` snapshot; updates are
  merged after the batch and visible in the next turn.
  """
  @callback call(args :: map(), context :: map()) ::
              {:ok, term()} | {:ok, term(), map()} | {:error, term()}

  @optional_callbacks [name: 1, description: 1, parameters: 1]

  defmacro __using__(_opts) do
    quote do
      @behaviour Condukt.Tool

      # Default: no-opts versions delegate to opts versions with empty list
      def name, do: name([])
      def description, do: description([])
      def parameters, do: parameters([])

      # Default opts implementations call the no-opts versions
      def name([]), do: raise("#{inspect(__MODULE__)} must implement name/0 or name/1")

      def description([]), do: raise("#{inspect(__MODULE__)} must implement description/0 or description/1")

      def parameters([]), do: raise("#{inspect(__MODULE__)} must implement parameters/0 or parameters/1")

      defoverridable name: 0, name: 1, description: 0, description: 1, parameters: 0, parameters: 1
    end
  end

  @doc """
  Gets the tool name for a tool spec.
  """
  def name(%Condukt.Tool.Inline{name: name}), do: name
  def name({module, opts}), do: module.name(opts)
  def name(module) when is_atom(module), do: module.name()

  @doc """
  Builds a tool specification for the LLM provider.
  """
  def to_spec(%Condukt.Tool.Inline{} = inline) do
    %{
      name: inline.name,
      description: inline.description,
      parameters: inline.parameters
    }
  end

  def to_spec({module, opts}) do
    %{
      name: module.name(opts),
      description: module.description(opts),
      parameters: module.parameters(opts)
    }
  end

  def to_spec(module) when is_atom(module) do
    %{
      name: module.name(),
      description: module.description(),
      parameters: module.parameters()
    }
  end

  @doc """
  Executes a tool by name with arguments.
  """
  def execute(%Condukt.Tool.Inline{call: call}, args, context) do
    context = Map.put(context, :opts, [])
    invoke_callable(call, args, context)
  end

  def execute({module, opts}, args, context) do
    context
    |> Map.put(:opts, opts)
    |> execute_call(module, args)
  end

  def execute(module, args, context) when is_atom(module) do
    context
    |> Map.put(:opts, [])
    |> execute_call(module, args)
  end

  defp execute_call(context, module, args) do
    module.call(args, context)
  catch
    :error, error -> {:error, format_error(error)}
  end

  defp invoke_callable(call, args, context) do
    call.(args, context)
  catch
    :error, error -> {:error, format_error(error)}
  end

  defp format_error(error) do
    if is_exception(error) do
      Exception.message(error)
    else
      inspect(error)
    end
  end
end
