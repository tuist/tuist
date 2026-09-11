defmodule Tuist.Kura.Rollouts.Notifier do
  @moduledoc """
  Best-effort Slack context for Kura rollout lifecycle transitions: start,
  pause (with the server and failing signal), completion, supersede, and
  expedite.

  Grafana is the paging authority; this is color, not detection. Delivery
  is fire-and-forget in a detached task — a webhook failure can never
  fail a reconciler tick — and a missing webhook URL disables the
  notifications entirely.
  """

  alias Tuist.Environment
  alias Tuist.Kura.Rollout

  def notify(event, %Rollout{} = rollout, metadata) do
    case Environment.ops_slack_webhook_url() do
      url when is_binary(url) and url != "" ->
        text = message(event, rollout, metadata)
        Task.start(fn -> deliver(url, text) end)
        :ok

      _ ->
        :ok
    end
  end

  defp deliver(url, text) do
    Req.post(url, json: %{text: text}, retry: false, receive_timeout: 5_000)
  end

  defp message(:started, rollout, metadata) do
    "Kura rollout started: `#{rollout.image_tag}` (#{rollout.mode}, from #{metadata[:source_tag] || "none"}) in #{environment()}"
  end

  defp message(:paused, rollout, metadata) do
    details =
      [
        metadata[:server_id] && "server #{metadata[:server_id]}",
        metadata[:region] && "region #{metadata[:region]}",
        metadata[:signal] && "signal #{metadata[:signal]}",
        metadata[:actor] && "by #{metadata[:actor]}"
      ]
      |> Enum.filter(& &1)
      |> Enum.join(", ")

    "Kura rollout paused: `#{rollout.image_tag}` at wave #{rollout.current_wave} in #{environment()}" <>
      if(details == "", do: "", else: " (#{details})")
  end

  defp message(:completed, rollout, _metadata) do
    "Kura rollout completed: `#{rollout.image_tag}` in #{environment()}"
  end

  defp message(:superseded, rollout, metadata) do
    "Kura rollout superseded: `#{rollout.image_tag}` -> `#{metadata[:superseded_by]}` in #{environment()}"
  end

  defp message(:expedited, rollout, metadata) do
    "Kura rollout expedited: `#{rollout.image_tag}` in #{environment()} by #{metadata[:actor] || "deploy input"}"
  end

  defp message(:resumed, rollout, metadata) do
    "Kura rollout resumed: `#{rollout.image_tag}` at wave #{rollout.current_wave} in #{environment()} by #{metadata[:actor]}"
  end

  defp message(:aborted, rollout, metadata) do
    "Kura rollout aborted: `#{rollout.image_tag}` in #{environment()} by #{metadata[:actor]}"
  end

  defp environment, do: Environment.env()
end
