defmodule Pulse.Errors.Supervisor do
  @moduledoc false
  use Pulse.Runtime.Supervision

  alias Pulse.Errors.Projection
  alias Pulse.Errors.Scope
  alias Pulse.Errors.Worker
  alias Pulse.Runtime
  alias Pulse.Runtime.Supervision, as: Supervisor

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  def children do
    opts = Runtime.get_env(:pulse, Projection, [])
    if opts[:enabled], do: [{__MODULE__, opts}], else: []
  end

  @impl true
  def init(opts) do
    Supervisor.init(
      [%{id: Scope, start: {:pg, :start_link, [Scope]}}, {Worker, opts}],
      strategy: :rest_for_one
    )
  end
end
