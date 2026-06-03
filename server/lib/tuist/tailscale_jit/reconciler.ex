defmodule Tuist.TailscaleJIT.Reconciler do
  @moduledoc """
  Boot-time recovery for the JIT elevation supervisor. Catches the
  window where the prod pod died between an elevation's TTL firing
  and the RevertWorker finishing: any `:active` Elevation row with
  `expires_at` in the past gets a fresh RevertWorker job. The
  periodic `DriftReconcilerWorker` is the steady-state authority;
  this is just the cold-start counterpart.
  """

  alias Tuist.TailscaleJIT.Approvals

  require Logger

  def child_spec(_arg) do
    %{
      id: __MODULE__,
      start: {Task, :start_link, [&run/0]},
      restart: :transient,
      type: :worker
    }
  end

  def run do
    Approvals.re_enqueue_expired_active_elevations()
    Logger.info("tailscale_jit: boot-time reconciler complete")
  end
end
