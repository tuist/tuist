defmodule Atlas.MCP.Proxy.StripeCallPolicy do
  @moduledoc """
  Judges each call to Stripe's hosted MCP server by its arguments.

  Stripe exposes every write as one tool, `stripe_api_write`, that takes any
  `POST`, `PATCH`, `PUT` or `DELETE` operation by its ID, so approving the tool
  would approve everything. Each call names its account (`stripe_context`) and
  mode (`livemode`), which Stripe requires to match that account, so the mode
  decides:

  - Test mode (sandboxes, the staging and canary accounts) runs without approval.
  - Live mode waits for the caller's own approval of that exact call in Atlas,
    whoever asks. A call that does not say `livemode: false` counts as live.
  - Meter events are refused in both modes. The Tuist server's usage sync is
    their only writer; a second one would bill customers twice.

  Stripe can additionally hold some live actions, such as refunds, for its own
  confirmation in the Stripe Dashboard.
  """

  @write_tool "stripe_api_write"
  @meter_event_operations ["PostBillingMeterEvent", "PostV2BillingMeterEvent"]

  def decide(@write_tool, arguments) do
    operation = arguments["stripe_api_operation_id"]

    cond do
      is_binary(operation) and String.starts_with?(operation, @meter_event_operations) ->
        {:deny,
         "meter events are only sent by the Tuist server's usage sync, and a second writer would double-bill customers."}

      arguments["livemode"] === false ->
        :allow

      true ->
        :approval_required
    end
  end

  def decide(_tool_name, _arguments), do: :allow

  def describe(@write_tool) do
    "Test-mode writes (livemode: false) run directly. Each live-mode write needs its own approval: the first call " <>
      "files a request and returns a link, the person approves it in Atlas, and the same call with identical " <>
      "arguments then runs once. Meter events are refused."
  end

  def describe(_tool_name), do: nil
end
