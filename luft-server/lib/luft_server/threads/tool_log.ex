defmodule LuftServer.Threads.ToolLog do
  @moduledoc "Reserves and records built-in tool effects through the run's database fence."
  @behaviour Condukt.Hooks

  alias LuftServer.Threads

  @impl true
  def before_tool(%{id: id, name: name, args: args}, context) do
    tools = context.opts[:tools]

    if name in tools,
      do: Threads.begin_tool_call(context.opts[:run], id, name, args, tools),
      else: :ok
  end

  @impl true
  def after_tool(%{id: id, name: name, args: args}, result, context) do
    if name in context.opts[:tools],
      do: Threads.complete_tool_call(context.opts[:run], id, name, args, result)

    :ok
  end
end
