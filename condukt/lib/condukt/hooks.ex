defmodule Condukt.Hooks do
  @moduledoc """
  Hooks step into the native agent loop: before and after each tool call, and
  when the model would end the run.

  A hook is a module implementing any of this behaviour's optional callbacks,
  listed as `module` or `{module, opts}` by the agent's `hooks/0` callback or
  the session's `:hooks` option. Hooks run as a chain in list order, and each
  callback receives the session's tool context with the hook's own `opts`.

  | Callback | Returns | Chain |
  | -------- | ------- | ----- |
  | `c:before_tool/2` | `:ok`, `{:rewrite, args}`, or `{:block, reason}` | Rewritten arguments pass on; the first block stops it. |
  | `c:after_tool/3` | `:ok` or `{:replace, result}` | The replaced result passes on. |
  | `c:on_yield/2` | `:ok` or `{:continue, message}` | The first continue stops it. |

  Each chain runs in its own process, linked below the run's worker. Aborting
  the run stops it, so a hook may wait on a person with `receive`, bounded by
  its own `after`, and needs no abort handling. A hook that crashes or returns
  anything else fails what it was deciding: the tool call gets an error
  result, or the answer stands. The crash is logged.

  Hooks hold no state of their own. Keep state that outlives a call, such as
  pending approvals or budgets, in a supervised process the hook talks to.
  See the Hooks guide for examples.
  """

  @doc """
  Runs before a tool call executes, with the call as
  `%{id: id, name: name, args: args}`.

  Return `{:rewrite, args}` to run the call with other arguments, which later
  hooks see, or `{:block, reason}` to skip the call and give the model an error
  result with `reason` instead.
  """
  @callback before_tool(call :: map(), context :: map()) :: :ok | {:rewrite, map()} | {:block, String.t()}

  @doc """
  Runs after a tool call, including calls a hook blocked and calls to unknown
  tools, with the arguments the call ran with and its result as `{:ok, value}`
  or `{:error, reason}`. Return `{:replace, result}` to change the result the
  model and later hooks see. A replaced `{:ok, value}` must be a string or
  encode as JSON, like a tool's result; otherwise the hook fails.
  """
  @callback after_tool(call :: map(), result :: {:ok, term()} | {:error, term()}, context :: map()) ::
              :ok | {:replace, {:ok, term()} | {:error, term()}}

  @doc """
  Runs when the model answers without tool calls, which would end the run,
  with the assistant `Condukt.Message`.

  Return `{:continue, message}` to add `message` as a user message and send the
  model back to work in the same run. Continued turns count against the run's
  `:max_turns`, and on the run's last turn this callback is not called.
  """
  @callback on_yield(message :: struct(), context :: map()) :: :ok | {:continue, String.t()}

  @optional_callbacks before_tool: 2, after_tool: 3, on_yield: 2

  @doc false
  # Hook specs as `{module, opts}`, or why the list is invalid.
  def normalize(hooks) when is_list(hooks) do
    Enum.reduce_while(hooks, {:ok, []}, fn spec, {:ok, acc} ->
      case normalize_spec(spec) do
        {:ok, hook} -> {:cont, {:ok, [hook | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> then(fn
      {:ok, hooks} -> {:ok, Enum.reverse(hooks)}
      error -> error
    end)
  end

  def normalize(hooks), do: {:error, {:invalid_hooks, hooks}}

  defp normalize_spec(module) when is_atom(module), do: normalize_spec({module, []})

  defp normalize_spec({module, opts} = spec) when is_atom(module) and is_list(opts) do
    case Code.ensure_loaded(module) do
      {:module, ^module} -> {:ok, spec}
      {:error, reason} -> {:error, {:hook_not_loaded, module, reason}}
    end
  end

  defp normalize_spec(spec), do: {:error, {:invalid_hook, spec}}

  @doc false
  # Returns the arguments to run the call with, or the reason it is blocked.
  def run_before_tool(hooks, call, context) do
    Enum.reduce_while(implementing(hooks, :before_tool, 2), {:ok, call.args}, fn {module, opts}, {:ok, args} ->
      case module.before_tool(%{call | args: args}, with_opts(context, opts)) do
        :ok -> {:cont, {:ok, args}}
        {:rewrite, args} when is_map(args) -> {:cont, {:ok, args}}
        {:block, reason} -> {:halt, {:block, reason}}
        other -> invalid_return!(module, :before_tool, other)
      end
    end)
  end

  @doc false
  def run_after_tool(hooks, call, result, context) do
    Enum.reduce(implementing(hooks, :after_tool, 3), result, fn {module, opts}, result ->
      case module.after_tool(call, result, with_opts(context, opts)) do
        :ok ->
          result

        {:replace, {:error, _reason} = replaced} ->
          replaced

        {:replace, {:ok, _value}} = replace ->
          encodable!(module, replace)

        other ->
          invalid_return!(module, :after_tool, other)
      end
    end)
  end

  @doc false
  def run_on_yield(hooks, message, context) do
    Enum.reduce_while(implementing(hooks, :on_yield, 2), :ok, fn {module, opts}, :ok ->
      case module.on_yield(message, with_opts(context, opts)) do
        :ok -> {:cont, :ok}
        {:continue, text} when is_binary(text) -> {:halt, {:continue, text}}
        other -> invalid_return!(module, :on_yield, other)
      end
    end)
  end

  # The model sees an `{:ok, value}` result as the value itself or its JSON,
  # so a replacement that cannot be encoded fails its hook here, in the hook's
  # process, instead of crashing the run when the next request is built.
  defp encodable!(_module, {:replace, {:ok, value} = replaced}) when is_binary(value), do: replaced

  defp encodable!(module, {:replace, {:ok, value} = replaced} = replace) do
    _ = JSON.encode!(value)
    replaced
  rescue
    _ -> invalid_return!(module, :after_tool, replace)
  end

  defp implementing(hooks, callback, arity) do
    Enum.filter(hooks, fn {module, _opts} -> function_exported?(module, callback, arity) end)
  end

  defp with_opts(context, opts), do: Map.put(context, :opts, opts)

  defp invalid_return!(module, callback, value) do
    raise ArgumentError, "#{inspect(module)}.#{callback} returned an invalid value: #{inspect(value)}"
  end
end
