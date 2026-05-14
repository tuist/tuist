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
end
