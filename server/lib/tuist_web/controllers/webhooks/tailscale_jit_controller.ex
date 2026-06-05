defmodule TuistWeb.Webhooks.TailscaleJITController do
  @moduledoc """
  HTTP-side of the JIT elevation bot. Two POST endpoints, both
  Slack-signed (verified by `TuistWeb.Plugs.SlackWebhookPlug`
  before the controller sees the request):

    * `/webhooks/tailscale-jit/slash` — receives the `/elevate`
      slash command. Parses `<env> [duration] <intent...>` from
      the `text` field and creates a Request via
      `Tuist.TailscaleJIT.Approvals.request_elevation/1`. Responds
      ephemerally to the requester.

    * `/webhooks/tailscale-jit/interactive` — receives Block Kit
      button callbacks (`approve`, `deny`, `revoke`). Parses the
      action_id + button value, enforces approver != requester for
      Approve (the matching check inside the transaction is the
      authoritative one), and routes to the right Approvals
      function.

  Slack expects a 200 response within 3 seconds. The work the
  controller dispatches (ACL mutation + Slack updates) happens
  inline here; if any operation grows past the 3s budget, move it
  into an Oban job and reply early.
  """

  use TuistWeb, :controller

  alias Tuist.TailscaleJIT.Approvals
  alias Tuist.TailscaleJIT.SlackBlocks
  alias Tuist.TailscaleJIT.SlackClient

  require Logger

  # Maps the env shorthand a user types in Slack to the matching
  # break-glass group bound by accessBindings on each cluster.
  @env_to_group %{
    "staging" => "group:tuist-staging-write",
    "canary" => "group:tuist-canary-write",
    "prod" => "group:tuist-prod-write",
    "production" => "group:tuist-prod-write"
  }

  @valid_envs Map.keys(@env_to_group)

  # ----------------------------------------------------------------
  # Slash command: POST /webhooks/tailscale-jit/slash
  # ----------------------------------------------------------------

  def slash(conn, %{"text" => raw_text} = params) do
    with {:ok, env, ttl, intent} <- parse_slash(raw_text),
         channel_id = approvals_channel(),
         {:ok, _request} <-
           Approvals.request_elevation(%{
             requester_email: slack_user_to_email(params["user_id"]),
             requester_slack_id: params["user_id"],
             target_group: Map.fetch!(@env_to_group, env),
             intent: intent,
             ttl_seconds: ttl,
             slack_channel_id: channel_id
           }) do
      json(conn, %{
        response_type: "ephemeral",
        text:
          "Request posted to <##{channel_id}>. A second human needs to approve within #{div(Approvals.approval_window_seconds(), 60)} min."
      })
    else
      {:error, reason} ->
        Logger.warning("tailscale_jit slash failed: #{inspect(reason)}")
        json(conn, %{response_type: "ephemeral", text: human_error(reason)})
    end
  end

  def slash(conn, _params) do
    json(conn, %{response_type: "ephemeral", text: usage_message()})
  end

  # ----------------------------------------------------------------
  # Interactive callback: POST /webhooks/tailscale-jit/interactive
  # ----------------------------------------------------------------

  def interactive(conn, %{"payload" => payload_json}) do
    case JSON.decode(payload_json) do
      {:ok, payload} -> dispatch_interactive(conn, payload)
      {:error, _} -> conn |> put_status(400) |> json(%{ok: false, error: "invalid payload"})
    end
  end

  def interactive(conn, _params) do
    conn |> put_status(400) |> json(%{ok: false, error: "missing payload"})
  end

  defp dispatch_interactive(conn, %{"actions" => [%{"action_id" => action_id, "value" => value} | _]} = payload) do
    user_slack_id = get_in(payload, ["user", "id"])
    user_email = slack_user_to_email(user_slack_id)
    channel_id = get_in(payload, ["channel", "id"])

    case action_id do
      "approve" ->
        do_approve(conn, value, user_slack_id, user_email, channel_id)

      "deny" ->
        do_deny(conn, value, user_slack_id, user_email)

      "revoke" ->
        do_revoke(conn, value, user_slack_id, user_email)

      other ->
        Logger.warning("tailscale_jit: unknown action #{inspect(other)}")
        send_resp(conn, 200, "")
    end
  end

  defp dispatch_interactive(conn, _payload) do
    send_resp(conn, 200, "")
  end

  defp do_approve(conn, value, actor_slack_id, actor_email, channel_id) do
    case SlackBlocks.decode_value(value) do
      {:ok, request_id, _requester_slack_id} ->
        # Single source of truth: Approvals.approve runs the policy
        # check inside the DB transaction. If self-approval is not
        # allowed for this requester + env, the transaction rolls
        # back with :cannot_self_approve and we surface that as an
        # ephemeral. Engineers requesting prod, plus anyone outside
        # the configured admin list requesting their own elevation
        # outside non-prod, end up here.
        case Approvals.approve(request_id, %{slack_id: actor_slack_id, email: actor_email}) do
          {:ok, _req, _elev} ->
            send_resp(conn, 200, "")

          {:error, :cannot_self_approve} ->
            SlackClient.ephemeral(
              channel_id,
              actor_slack_id,
              ":no_entry: A second human has to click Approve for this env. " <>
                "(Production writes always require a second approver, even for engineers.)"
            )

            send_resp(conn, 200, "")

          {:error, :approval_expired} ->
            SlackClient.ephemeral(
              channel_id,
              actor_slack_id,
              ":hourglass: This elevation request has expired. Run `/elevate` again to create a fresh one."
            )

            send_resp(conn, 200, "")

          {:error, reason} ->
            SlackClient.ephemeral(channel_id, actor_slack_id, "Approval failed: #{human_error(reason)}")
            send_resp(conn, 200, "")
        end

      :error ->
        send_resp(conn, 200, "")
    end
  end

  defp do_deny(conn, value, actor_slack_id, actor_email) do
    case SlackBlocks.decode_value(value) do
      {:ok, request_id, _} ->
        _ = Approvals.deny(request_id, %{slack_id: actor_slack_id, email: actor_email})
        send_resp(conn, 200, "")

      :error ->
        send_resp(conn, 200, "")
    end
  end

  defp do_revoke(conn, value, actor_slack_id, actor_email) do
    case Integer.parse(value) do
      {elev_id, ""} ->
        _ = Approvals.revoke(elev_id, %{slack_id: actor_slack_id, email: actor_email})
        send_resp(conn, 200, "")

      _ ->
        send_resp(conn, 200, "")
    end
  end

  # ----------------------------------------------------------------
  # Parsing + helpers
  # ----------------------------------------------------------------

  # Accepted forms (whitespace-separated):
  #   "<env> <intent...>"                     -> default TTL
  #   "<env> <duration> <intent...>"          -> explicit TTL
  # Duration: "15m", "30m", "1h", or bare integer seconds.
  defp parse_slash(text) when is_binary(text) do
    case_result =
      case text |> String.trim() |> String.split(~r/\s+/, parts: 3) do
        [env | _] when env not in @valid_envs ->
          {:error, {:invalid_env, env}}

        [env, maybe_duration, rest] ->
          case parse_duration(maybe_duration) do
            {:ok, seconds} -> {:ok, env, seconds, String.trim(rest)}
            :error -> {:ok, env, Approvals.default_ttl_seconds(), String.trim("#{maybe_duration} #{rest}")}
          end

        [env, rest] ->
          {:ok, env, Approvals.default_ttl_seconds(), String.trim(rest)}

        _ ->
          {:error, :missing_intent}
      end

    validate_intent(case_result)
  end

  defp parse_slash(_), do: {:error, :missing_text}

  defp validate_intent({:ok, env, ttl, intent}) when byte_size(intent) >= 5, do: {:ok, env, ttl, intent}
  defp validate_intent({:ok, _env, _ttl, _short}), do: {:error, :intent_too_short}
  defp validate_intent(other), do: other

  defp parse_duration(s) when is_binary(s) do
    cond do
      Regex.match?(~r/^\d+m$/, s) ->
        {n, "m"} = Integer.parse(s)
        {:ok, n * 60}

      Regex.match?(~r/^\d+h$/, s) ->
        {n, "h"} = Integer.parse(s)
        {:ok, n * 3600}

      Regex.match?(~r/^\d+$/, s) ->
        {n, ""} = Integer.parse(s)
        {:ok, n}

      true ->
        :error
    end
  end

  defp human_error({:invalid_env, env}), do: "Unknown env `#{env}`. Use one of: #{Enum.join(@valid_envs, ", ")}."
  defp human_error(:missing_intent), do: usage_message()
  defp human_error(:missing_text), do: usage_message()
  defp human_error(:intent_too_short), do: "Intent must be at least 5 characters."
  defp human_error(reason), do: "Internal error: #{inspect(reason)}"

  defp usage_message do
    "Usage: `/elevate <env> [duration] <intent>` where env is one of #{Enum.join(@valid_envs, ", ")}. Duration is e.g. `15m` or `1h` (default #{div(Approvals.default_ttl_seconds(), 60)}m, max #{div(Approvals.max_ttl_seconds(), 60)}m). Intent should describe what you're going to do."
  end

  # Maps a Slack user id to the tailnet identity (email). Calls
  # Slack `users.info` which requires the bot app to hold the
  # `users:read` + `users:read.email` scopes. Assumes Slack
  # workspace email == tailnet login email, which is true for our
  # team (everyone uses tuist.dev for both). Failures return nil
  # so the caller can reject the request rather than mutate the
  # ACL for a phantom identity.
  defp slack_user_to_email(slack_user_id) when is_binary(slack_user_id) do
    case SlackClient.user_email(slack_user_id) do
      {:ok, email} ->
        email

      {:error, reason} ->
        Logger.warning("tailscale_jit: failed to resolve Slack user #{slack_user_id} email: #{inspect(reason)}")
        nil
    end
  end

  defp slack_user_to_email(_), do: nil

  defp approvals_channel do
    Tuist.Environment.tailscale_jit_approvals_channel_id() || "#tailscale-jit-approvals"
  end
end
