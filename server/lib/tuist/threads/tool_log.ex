defmodule Tuist.Threads.ToolLog do
  @moduledoc """
  A `Condukt.Hooks` hook that keeps a thread's record of the built-in tool
  calls its run makes: before a call runs it reserves the effect and shows
  the running tool message (`Threads.begin_tool_call/5`), and once the call
  has its final result, after any park, it completes them
  (`Threads.complete_tool_call/5`). Tools that record themselves, such as the
  MCP tools through `Threads.call_external_tool/5`, are left out by listing
  only the built-ins in `:tools`.

  Options: `:run` and `:tools`, the tool names it records.
  """

  @behaviour Condukt.Hooks

  alias Tuist.Threads

  @impl true
  def before_tool(%{id: id, name: name, args: args}, context) do
    tools = context.opts[:tools]
    if name in tools, do: Threads.begin_tool_call(context.opts[:run], id, name, args, tools), else: :ok
  end

  @impl true
  def after_tool(%{id: id, name: name, args: args}, result, context) do
    if name in context.opts[:tools], do: Threads.complete_tool_call(context.opts[:run], id, name, args, result)
    :ok
  end
end
