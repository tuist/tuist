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

  ## Waiting Without Holding a Process

  A tool that waits for the outside world, such as a CI webhook, a person's
  answer, or a slow job, returns `{:park, state, opts}` instead of a result,
  much as a `GenServer` returns `{:noreply, state, timeout}`. No tool code runs
  and the tool timeout does not apply while the call is parked. When a signal
  or its deadline arrives, the session calls
  `c:wake/3` with the event and `state`, and `c:cancel/2` with `state` if the
  turn is aborted first. See `Condukt.Park` and the
  [Waiting for Events](parking.md) guide.

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

  ## Aborts

  Each call runs in its own process, linked to the turn that made it.
  Aborting the turn shuts the turn down, and the link takes the call with it,
  along with any processes the call linked to itself, such as a sub-agent's
  session. A call that must not stop halfway, because it would leave a side
  effect half done, opts out with `c:on_abort/1`:

      @impl true
      def on_abort(_opts), do: :finish

  Its process then traps exits while it runs, so the abort arrives as an
  `{:EXIT, pid, :shutdown}` message. The call can ignore it and run to the end,
  or receive it, clean up, and stop. Either way its result reaches nobody,
  because the turn is over.

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
    * `{:park, state, opts}` — the call waits for a signal or a time.
      `c:wake/3` receives the event and `state`. See
      `Condukt.Park`.

  Within a single batch of tool calls in one assistant message, each tool
  starts from the same start-of-batch `assigns` snapshot; updates are
  merged after the batch and visible in the next turn.
  """
  @callback call(args :: map(), context :: map()) ::
              {:ok, term()} | {:ok, term(), map()} | {:error, term()} | {:park, term(), keyword()}

  @doc """
  What happens to a running call when its turn is aborted: `:kill`, the
  default, stops it, and `:finish` lets it run to the end. See "Aborts".
  """
  @callback on_abort(opts :: keyword()) :: :kill | :finish

  @doc """
  Handles the event that wakes a parked call.

  `event` is `{:signal, {kind, key}, value}`, with the value the signal kind's
  `cast/1` returned, or `:timeout` when the park's deadline came first.
  `state` is the term the call parked with. Returns what `c:call/2` returns,
  so a call can park again, for example to poll once more.

  A tool that parks must implement it.
  """
  @callback wake(event :: term(), state :: term(), context :: map()) ::
              {:ok, term()} | {:ok, term(), map()} | {:error, term()} | {:park, term(), keyword()}

  @doc """
  Cleans up external work when the turn is aborted while the call is parked.

  Like `c:GenServer.terminate/2`, it receives the call's last parked `state`.
  It runs in its own process, also for a woken call that is aborted before it
  parks again or returns, and may run more than once, so keep it idempotent.
  Its return value is ignored.
  """
  @callback cancel(state :: term(), context :: map()) :: term()

  @optional_callbacks [name: 1, description: 1, parameters: 1, on_abort: 1, wake: 3, cancel: 2]

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
  Returns what aborting the turn does to a running call of the tool: `:kill`
  unless the tool asks to `:finish`.
  """
  def on_abort(%Condukt.Tool.Inline{on_abort: on_abort}), do: on_abort
  def on_abort({module, opts}), do: module_on_abort(module, opts)
  def on_abort(module) when is_atom(module), do: module_on_abort(module, [])

  defp module_on_abort(module, opts) do
    if function_exported?(module, :on_abort, 1), do: module.on_abort(opts), else: :kill
  end

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

  @doc """
  Whether a tool implements `c:wake/3`, which parking requires.
  """
  def wakes?(%Condukt.Tool.Inline{wake: wake}), do: is_function(wake, 3)
  def wakes?({module, _opts}), do: wakes?(module)
  def wakes?(module) when is_atom(module), do: Code.ensure_loaded?(module) and function_exported?(module, :wake, 3)

  @doc """
  Runs a tool's `c:wake/3` for a parked call.
  """
  def wake(%Condukt.Tool.Inline{wake: wake}, event, state, context) do
    guard(fn -> wake.(event, state, Map.put(context, :opts, [])) end)
  end

  def wake({module, opts}, event, state, context) do
    guard(fn -> module.wake(event, state, Map.put(context, :opts, opts)) end)
  end

  def wake(module, event, state, context) when is_atom(module) do
    guard(fn -> module.wake(event, state, Map.put(context, :opts, [])) end)
  end

  @doc """
  Runs a tool's `c:cancel/2`, when it has one.
  """
  def cancel(%Condukt.Tool.Inline{cancel: nil}, _state, _context), do: :ok

  def cancel(%Condukt.Tool.Inline{cancel: cancel}, state, context) do
    guard(fn -> cancel.(state, Map.put(context, :opts, [])) end)
  end

  def cancel({module, opts}, state, context), do: cancel_module(module, state, Map.put(context, :opts, opts))
  def cancel(module, state, context) when is_atom(module), do: cancel_module(module, state, Map.put(context, :opts, []))

  defp cancel_module(module, state, context) do
    if Code.ensure_loaded?(module) and function_exported?(module, :cancel, 2) do
      guard(fn -> module.cancel(state, context) end)
    else
      :ok
    end
  end

  defp guard(fun) do
    fun.()
  catch
    :error, error -> {:error, format_error(error)}
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
