defmodule Tuist.Application.RuntimeChildren do
  @moduledoc """
  Pure functions deriving supervision-tree children from pod role.

  Lifted out of `Tuist.Application` so they can be unit-tested against
  every value of `Tuist.Environment.modes/0`. Mirrors the rationale in
  `Tuist.Oban.RuntimeConfig`: keep mode-specific gates expressed as
  allowlists (`mode == :web`) rather than denylists of known non-web
  modes, so a future role (`:scheduler`, `:ingest`, ...) is excluded by
  default and has to opt in.
  """

  @sweeper_interval_ms 60 * 60 * 1000

  @doc """
  Child spec list for `Guardian.DB.Sweeper`, gated on pod mode.

  Returns the sweeper for `:web`; empty for every other mode. Refresh
  tokens are only issued and verified by the Phoenix endpoint, and
  non-web pods connect with a DB role that lacks privileges on
  `guardian_tokens` — running the sweeper there fails every interval
  with `permission denied`.
  """
  def guardian_db_sweeper(:web), do: [{Guardian.DB.Sweeper, [interval: @sweeper_interval_ms]}]
  def guardian_db_sweeper(_), do: []

  @doc """
  Child specs for the Open Graph image renderer, gated on pod mode.

  Returns the headless-browser pool and its task supervisor for `:web`;
  empty for every other mode. The renderer is reached only through the
  `TuistWeb` Open Graph endpoints, and the non-web images run on VMs
  without Chrome installed — `Browse.Pool.init_worker/1` raises
  `:chrome_not_found` there. NimblePool catches that raise, drops the
  worker and re-sends itself `:init_worker` with no backoff, so the pool
  stays up and retries forever (measured at ~120 failures per second on
  both xcresult-processor replicas), burning CPU on hosts whose only job
  is CPU-bound xcresult parsing and flooding Sentry. `start_pool/1` cannot
  intercept it: `NimblePool.start_link/2` has already returned `{:ok, pid}`
  by then, so the `:ignore` branch never runs.
  """
  def open_graph_image_renderer(:web) do
    [
      {Task.Supervisor, name: Tuist.OpenGraphImageRenderer.TaskSupervisor},
      Tuist.OpenGraphImageRenderer
    ]
  end

  def open_graph_image_renderer(_), do: []

  @doc """
  Child spec for the marketing stats poller, gated on pod mode.

  Returns the poller for `:web`; empty for every other mode. It polls
  ClickHouse every 5 seconds and broadcasts over PubSub purely to feed
  the marketing LiveViews, which only the Phoenix endpoint serves.
  """
  def marketing_stats(:web), do: [Tuist.Marketing.Stats]
  def marketing_stats(_), do: []
end
