defmodule Pulse.Runtime.Server do
  @moduledoc false
  use GenServer

  @impl true
  def init({runtime, module, args}) do
    Pulse.Runtime.install(runtime)
    Process.put({__MODULE__, :module}, module)
    module.init(args)
  end

  @impl true
  def handle_call(message, from, state), do: module().handle_call(message, from, state)
  @impl true
  def handle_cast(message, state), do: module().handle_cast(message, state)
  @impl true
  def handle_info(message, state), do: module().handle_info(message, state)
  @impl true
  def handle_continue(message, state), do: module().handle_continue(message, state)
  @impl true
  def terminate(reason, state) do
    module = module()
    if function_exported?(module, :terminate, 2), do: module.terminate(reason, state), else: :ok
  end

  @impl true
  def code_change(old, state, extra) do
    module = module()
    if function_exported?(module, :code_change, 3), do: module.code_change(old, state, extra), else: {:ok, state}
  end

  @impl true
  def format_status(status) do
    module = module()
    if function_exported?(module, :format_status, 1), do: module.format_status(status), else: status
  end

  defp module, do: Process.get({__MODULE__, :module})
end
