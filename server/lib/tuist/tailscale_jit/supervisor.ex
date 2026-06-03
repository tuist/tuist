defmodule Tuist.TailscaleJIT.Supervisor do
  @moduledoc """
  Supervises the JIT elevation bot's runtime processes. Started
  ONLY when `Tuist.Environment.web?() and
  Tuist.Environment.env() == :prod and
  Tuist.Environment.tuist_hosted?()` because the tailnet ACL is a
  single global resource and we want one writer. Staging and
  canary pods compile the code (so breakage shows up at CI) but
  don't start the supervisor.

  `rest_for_one` means if the reconciler crashes on boot, nothing
  downstream tries to run against a half-reconciled state. The
  Oban workers themselves live in the main Oban supervision tree;
  they don't need to be here.
  """

  use Supervisor

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      Tuist.TailscaleJIT.Reconciler
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
