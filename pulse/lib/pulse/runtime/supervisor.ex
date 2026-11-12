defmodule Pulse.Runtime.Supervisor do
  @moduledoc false
  use Supervisor

  @impl true
  def init({runtime, module, args}) do
    Pulse.Runtime.install(runtime)
    module.init(args)
  end
end
