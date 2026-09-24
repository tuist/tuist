defmodule Atlas.Nudges.SlackActions do
  @moduledoc """
  Slack interaction dispatch for nudge cards. Resolves the Slack actor to
  an Atlas user, checks scope, then mutates the nudge under a row lock
  (see `Atlas.Nudges.claim/2`, `release/1`, `dismiss/3`).
  """

  alias Atlas.Nudges
  alias Atlas.Nudges.SlackNotifier
  alias Atlas.Slack.API
  alias Atlas.Users
  alias Atlas.Users.User

  require Logger

  def handle_slack_action(action, nudge_id, opts \\ []) do
    actor = slack_actor(opts)

    with %User{} = actor <- actor,
         true <- Users.has_scope?(actor, "accounts:write") do
      case action do
        "claim" -> claim(nudge_id, actor)
        "release" -> release(nudge_id)
        "send" -> send_email(nudge_id, actor)
        "retry" -> retry(nudge_id)
        "dismiss" -> dismiss(nudge_id)
        _action -> {:error, :unsupported_nudge_action}
      end
    else
      nil -> {:error, :nudge_actor_required}
      false -> {:error, :nudge_scope_required}
    end
    |> refresh_card()
    |> action_message(action)
  end

  defp claim(nudge_id, actor) do
    case Nudges.claim(nudge_id, actor) do
      {:ok, nudge} -> {:ok, nudge}
      {:error, :not_found} -> {:error, :nudge_not_found}
      other -> other
    end
  end

  defp release(nudge_id) do
    case Nudges.release(nudge_id) do
      {:ok, nudge} -> {:ok, nudge}
      {:error, :not_found} -> {:error, :nudge_not_found}
      other -> other
    end
  end

  defp dismiss(nudge_id) do
    case Nudges.dismiss(nudge_id, %{dismissed_reason: "Dismissed from Slack"}) do
      {:ok, nudge} -> {:ok, nudge}
      {:error, :not_found} -> {:error, :nudge_not_found}
      other -> other
    end
  end

  defp send_email(nudge_id, actor) do
    case Nudges.send(nudge_id, actor) do
      {:ok, nudge} -> {:ok, nudge}
      {:error, :not_found} -> {:error, :nudge_not_found}
      other -> other
    end
  end

  defp retry(nudge_id) do
    case Nudges.retry(nudge_id) do
      {:ok, nudge} -> {:ok, nudge}
      {:error, :not_found} -> {:error, :nudge_not_found}
      other -> other
    end
  end

  defp refresh_card({:ok, nudge} = ok) do
    _ = maybe_update_card(nudge)
    ok
  end

  defp refresh_card(other), do: other

  defp maybe_update_card(nudge) do
    case nudge do
      %{slack_channel_id: nil} ->
        :ok

      %{slack_channel_id: channel, slack_message_ts: ts}
      when is_binary(channel) and is_binary(ts) ->
        stage = Nudges.stage_for(nudge)

        case API.update_message(
               :company,
               channel,
               ts,
               "Account nudge: #{nudge.title}",
               SlackNotifier.build_blocks(nudge, expired: false, stage: stage),
               metadata: %{
                 event_type: "atlas_nudge",
                 event_payload: %{key: Nudges.post_attempt_client_msg_id(nudge)}
               }
             ) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.warning("Failed to refresh Slack nudge card for nudge=#{nudge.id}: #{inspect(reason)}")

            :ok
        end

      _ ->
        :ok
    end
  end

  defp slack_actor(opts) do
    case Keyword.get(opts, :actor_email) do
      email when is_binary(email) and email != "" -> Users.get_user_by_email(email)
      _ -> nil
    end
  end

  defp action_message({:ok, nudge}, "claim"), do: {:ok, %{message: "You now own: #{nudge.title}"}}

  defp action_message({:ok, nudge}, "release"), do: {:ok, %{message: "Released: #{nudge.title}"}}

  defp action_message({:ok, nudge}, "dismiss"), do: {:ok, %{message: "Dismissed: #{nudge.title}"}}

  defp action_message({:ok, %{duplicate: true} = nudge}, "send"),
    do: {:ok, %{message: "Already queued: #{nudge.title}"}}

  defp action_message({:ok, nudge}, "send"), do: {:ok, %{message: "Email queued: #{nudge.title}"}}

  defp action_message({:ok, nudge}, "retry"), do: {:ok, %{message: "Ready to resend: #{nudge.title}"}}

  defp action_message({:error, reason}, _action), do: {:error, reason}
end
