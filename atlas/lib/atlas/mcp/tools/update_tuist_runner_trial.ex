defmodule Atlas.MCP.Tools.UpdateTuistRunnerTrial do
  @moduledoc "Starts or cancels a Tuist account's runner trial through the audited internal API, as the ops account page does, or adds the runner items a paid subscription lacks."

  use Atlas.MCP.Tool,
    name: "update_tuist_runner_trial",
    schema: Atlas.TuistAccounts.update_runner_trial_schema(),
    output_schema: Atlas.TuistAccounts.runner_billing_output_schema()

  alias Atlas.MCP.Tool
  alias Atlas.TuistAccounts
  alias Atlas.TuistFeatureFlags

  @impl EMCP.Tool
  def description do
    "Start or cancel a Tuist account's runner trial, as the ops account page's buttons do. operation: start puts the " <>
      "account on an open-ended trial: runner usage is still metered but not billed, the runner items come off its " <>
      "Stripe subscription, and Air's free-tier caps (runner allowance, cache caps and their emails) stop applying. " <>
      "It is refused (already_on_trial) while a trial runs. cancel ends the trial: the runner items are added to the " <>
      "live subscription without proration, so runner usage is billable from then on and trial usage stays free. " <>
      "An account with no paid plan has no subscription to add them to, so cancelling falls back to Air's caps " <>
      "and leaves runner usage unbilled; that is refused (paid_plan_required) unless confirm_air_limits is true. " <>
      "Get the account onto Pro or Enterprise first when it should keep using runners pay as you go. " <>
      "operation: add_runner_items is for a Pro or Enterprise account that is not on a trial but whose subscription " <>
      "lacks the runner items, such as one that subscribed before runner pricing existed: it adds them without " <>
      "proration, so runner usage is billable from then on and earlier usage stays free. It is refused with " <>
      "on_trial (cancel the trial instead), paid_plan_required, or runner_items_present when there is nothing to add. " <>
      "Requires feature_flags:write. Read get_tuist_runner_billing first and supply its revision as expected_revision, " <>
      "a reason and a unique change_id UUID. A stale revision is rejected (409): re-read before deciding again. Writes " <>
      "never retry automatically; after an ambiguous failure, re-read the billing state and repeat with the SAME " <>
      "change_id and payload, which returns the recorded result when it was applied. Returns the runner billing state " <>
      "after the change. Each write needs the approval of the person you work for: the first call files a request and " <>
      "returns a link, the person approves it in Atlas, and the same call with identical arguments then runs once. " <>
      "Never approve it yourself."
  end

  def execute(conn, args) do
    TuistAccounts.update_runner_trial(Tool.current_user(conn), args, TuistFeatureFlags.execution_opts(conn))
  end
end
