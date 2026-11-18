defmodule Atlas.MCP.Tools.UpdateTuistRunnerConcurrencyLimits do
  @moduledoc "Sets one platform's runner concurrency limits for a Tuist account through the audited internal API."

  use Atlas.MCP.Tool,
    name: "update_tuist_runner_concurrency_limits",
    schema: Atlas.TuistAccounts.update_limits_schema(),
    output_schema: Atlas.TuistAccounts.limits_output_schema()

  alias Atlas.MCP.Tool
  alias Atlas.TuistAccounts
  alias Atlas.TuistFeatureFlags

  @impl EMCP.Tool
  def description do
    "Set one platform's (linux or macos) runner concurrency limits for a Tuist account: both vcpus and memory_gb, as positive " <>
      "integers; the other platform is unchanged. Requires feature_flags:write. Read get_tuist_runner_concurrency_limits first and " <>
      "supply its revision as expected_revision, a reason and a unique change_id UUID. Lowering a limit below current usage " <>
      "does not stop running jobs; new jobs wait until usage fits. A stale revision is rejected (409), including after an " <>
      "ops dashboard edit: re-read before deciding again. Writes never retry automatically; after an ambiguous failure, " <>
      "reconcile using the SAME change_id and original payload. Actor and interface come from the authenticated session. " <>
      "Each write needs the approval of the person you work for: the first call files a request and returns a link, the person " <>
      "approves it in Atlas, and the same call with identical arguments then runs once. Never approve it yourself."
  end

  def execute(conn, args) do
    TuistAccounts.update_limits(Tool.current_user(conn), args, TuistFeatureFlags.execution_opts(conn))
  end
end
