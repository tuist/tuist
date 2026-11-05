defmodule TuistOpsWeb.SlackController do
  @moduledoc """
  HTTP-side of the JIT elevation bot. Two POST endpoints, both
  Slack-signed (verified by `TuistOpsWeb.Plugs.SlackWebhookPlug`
  before the controller sees the request):

    * `/webhooks/slack/slash` — receives the `/elevate` slash
      command. Parses `<env> [duration] <intent...>` from the
      `text` field and creates a Request via
      `TuistOps.JIT.Approvals.request_elevation/1`. Responds
      ephemerally to the requester. `/elevate-github` takes
      `<login> [duration] <intent...>` instead and requests a
      GitHub organization admin elevation for that login.

    * `/webhooks/slack/interactive` — receives Block Kit button
      callbacks (`approve`, `deny`, `revoke`). Parses the action_id
      + button value and routes to the right Approvals function;
      the policy gate inside the DB transaction is the
      authoritative check.

  Slack expects a 200 response within 3 seconds. The work the
  controller dispatches (DB writes + Slack updates) happens inline
  here; if any operation grows past the 3s budget, move it into an
  Oban job and reply early.
  """

  use TuistOpsWeb, :controller

  alias TuistOps.JIT.Approvals
  alias TuistOps.JIT.Policy
  alias TuistOps.JIT.Request
  alias TuistOps.Environment
  alias TuistOps.JIT.SlackBlocks
  alias TuistOps.JIT.SlackClient
  alias TuistOps.ProjectAccess.Approvals, as: ProjectAccessApprovals
  alias TuistOps.ProjectAccess.SlackBlocks, as: ProjectAccessSlackBlocks

  require Logger

  # Maps the env shorthand a user types in Slack to the target
  # group identifier persisted on the Request row. The group
  # string is opaque to the gateway path; the Policy module
  # decodes it back to an env name when needed.
  #
  # `staging` stays in the map on purpose even though it can no
  # longer be elevated: keeping it here is what lets `parse_slash`
  # answer "/elevate staging" with "you already have write" rather
  # than "unknown env". `elevatable_envs/0` is the list the command
  # actually accepts.
  @env_to_group %{
    "staging" => "group:tuist-staging-write",
    "canary" => "group:tuist-canary-write",
    "prod" => "group:tuist-production-write",
    "production" => "group:tuist-production-write"
  }

  @valid_envs Map.keys(@env_to_group)

  # ----------------------------------------------------------------
  # Slash command: POST /webhooks/slack/slash
  # ----------------------------------------------------------------

  def slash(conn, %{"command" => "/elevate-github"} = params) do
    params
    |> Map.get("text", "")
    |> parse_github_slash()
    |> request_elevation(conn, params)
  end

  def slash(conn, %{"text" => raw_text} = params) do
    raw_text
    |> parse_slash()
    |> request_elevation(conn, params)
  end

  def slash(conn, _params) do
    json(conn, %{response_type: "ephemeral", text: usage_message()})
  end

  defp request_elevation(parse_result, conn, params) do
    with {:ok, parsed} <- parse_result,
         channel_id = approvals_channel(),
         {:ok, _request} <-
           Approvals.request_elevation(%{
             requester_email: slack_user_to_email(params["user_id"]),
             requester_slack_id: params["user_id"],
             target_group: parsed.target_group,
             github_login: parsed[:github_login],
             orb_thread_id: parsed[:orb_thread_id],
             intent: parsed.intent,
             ttl_seconds: parsed.ttl,
             slack_channel_id: channel_id
           }) do
      json(conn, %{
        response_type: "ephemeral",
        text:
          "Request posted to <##{channel_id}>. A second human needs to approve within #{div(Approvals.approval_window_seconds(), 60)} min."
      })
    else
      {:error, reason} ->
        Logger.warning("tuist_ops slash failed: #{inspect(reason)}")
        json(conn, %{response_type: "ephemeral", text: human_error(reason)})
    end
  end

  # ----------------------------------------------------------------
  # Interactive callback: POST /webhooks/slack/interactive
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

  defp dispatch_interactive(
         conn,
         %{"actions" => [%{"action_id" => action_id, "value" => value} | _]} = payload
       ) do
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

      "pa_approve" ->
        do_pa_approve(conn, value, user_slack_id, user_email, channel_id)

      "pa_deny" ->
        do_pa_deny(conn, value, user_slack_id, user_email)

      other ->
        Logger.warning("tuist_ops: unknown action #{inspect(other)}")
        send_resp(conn, 200, "")
    end
  end

  defp dispatch_interactive(conn, _payload) do
    send_resp(conn, 200, "")
  end

  defp do_approve(conn, value, actor_slack_id, actor_email, channel_id) do
    case SlackBlocks.decode_value(value) do
      {:ok, request_id, _requester_slack_id} ->
        case Approvals.approve(request_id, %{slack_id: actor_slack_id, email: actor_email}) do
          {:ok, _req, _elev} ->
            send_resp(conn, 200, "")

          {:error, :cannot_self_approve} ->
            SlackClient.ephemeral(
              channel_id,
              actor_slack_id,
              ":no_entry: Your Tailscale role can't self-approve elevations — " <>
                "self-approval is limited to engineering roles (Owner, Admin, or Member). " <>
                "Ask an Owner, Admin, or Member to click Approve."
            )

            send_resp(conn, 200, "")

          {:error, :approval_expired} ->
            SlackClient.ephemeral(
              channel_id,
              actor_slack_id,
              ":hourglass: This elevation request has expired. Run `/elevate` again to create a fresh one."
            )

            send_resp(conn, 200, "")

          {:error, :approver_not_authorized} ->
            SlackClient.ephemeral(
              channel_id,
              actor_slack_id,
              ":no_entry: Your Tailscale role can't approve elevations. " <>
                "Only engineering roles (Owner, Admin, or Member) can approve; " <>
                "Auditor/Billing-admin and off-tailnet identities can't."
            )

            send_resp(conn, 200, "")

          {:error, reason} ->
            SlackClient.ephemeral(
              channel_id,
              actor_slack_id,
              "Approval failed: #{human_error(reason)}"
            )

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
  # Operator project-access (admin tier) approve / deny
  # ----------------------------------------------------------------

  defp do_pa_approve(conn, value, actor_slack_id, actor_email, channel_id) do
    case ProjectAccessSlackBlocks.decode_value(value) do
      {:ok, request_id} ->
        case ProjectAccessApprovals.approve(request_id, %{
               slack_id: actor_slack_id,
               email: actor_email
             }) do
          {:ok, _req, _grant} ->
            send_resp(conn, 200, "")

          {:error, :cannot_self_approve} ->
            pa_ephemeral(
              conn,
              channel_id,
              actor_slack_id,
              ":no_entry: Only Owners/Admins can self-approve admin access to a customer org. You'll need a second human to click Approve."
            )

          {:error, :approver_not_authorized} ->
            pa_ephemeral(
              conn,
              channel_id,
              actor_slack_id,
              ":no_entry: Approving admin access to a customer org requires an Owner or Admin role on the tailnet."
            )

          {:error, :approval_expired} ->
            pa_ephemeral(
              conn,
              channel_id,
              actor_slack_id,
              ":hourglass: This access request has expired. The operator needs to start again."
            )

          {:error, reason} ->
            pa_ephemeral(
              conn,
              channel_id,
              actor_slack_id,
              "Approval failed: #{human_error(reason)}"
            )
        end

      :error ->
        send_resp(conn, 200, "")
    end
  end

  defp do_pa_deny(conn, value, actor_slack_id, actor_email) do
    case ProjectAccessSlackBlocks.decode_value(value) do
      {:ok, request_id} ->
        _ =
          ProjectAccessApprovals.deny(request_id, %{slack_id: actor_slack_id, email: actor_email})

        send_resp(conn, 200, "")

      :error ->
        send_resp(conn, 200, "")
    end
  end

  defp pa_ephemeral(conn, channel_id, actor_slack_id, text) do
    SlackClient.ephemeral(channel_id, actor_slack_id, text)
    send_resp(conn, 200, "")
  end

  # ----------------------------------------------------------------
  # Parsing + helpers
  # ----------------------------------------------------------------

  # Accepted forms (whitespace-separated):
  #   "<env> <intent...>"                     -> default TTL
  #   "<env> <duration> <intent...>"          -> explicit TTL
  # Duration: "15m", "30m", "1h", or bare integer seconds.
  defp parse_slash(text) when is_binary(text) do
    case text |> String.trim() |> String.split(~r/\s+/, parts: 2) do
      [env | _] when env not in @valid_envs ->
        {:error, {:invalid_env, env}}

      [env, rest] ->
        with false <- Policy.always_write_env?(env),
             {:ok, thread_id, rest} <- parse_thread_flag(rest) do
          rest
          |> parse_duration_and_intent()
          |> Map.put(:target_group, Map.fetch!(@env_to_group, env))
          |> Map.put(:orb_thread_id, thread_id)
          |> validate_intent()
        else
          true -> {:error, {:always_write_env, env}}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, :missing_intent}
    end
  end

  defp parse_slash(_), do: {:error, :missing_text}

  # `--thread <T-…>` right after the env aims the elevation at one Amp
  # orb thread instead of the requester's own kubectl. Agents propose
  # this exact command; the human runs it and approves it.
  defp parse_thread_flag(text) do
    case String.split(text, ~r/\s+/, parts: 3) do
      ["--thread", thread_id, rest] ->
        if Request.orb_thread_id?(thread_id),
          do: {:ok, thread_id, rest},
          else: {:error, {:invalid_thread_id, thread_id}}

      ["--thread" | _] ->
        {:error, :missing_intent}

      _ ->
        # A flag anywhere else, or one Slack turned into an em or en
        # dash, would otherwise fall through to a personal elevation of
        # the requester with the flag buried in the intent.
        if Regex.match?(~r/(--|\x{2014}|\x{2013})thread/iu, text),
          do: {:error, :misplaced_thread_flag},
          else: {:ok, nil, text}
    end
  end

  # `/elevate-github` takes "<login> [duration] <intent...>".
  defp parse_github_slash(text) when is_binary(text) do
    case text |> String.trim() |> String.split(~r/\s+/, parts: 2) do
      [login, rest] ->
        if Regex.match?(Request.github_login_format(), login) do
          rest
          |> parse_duration_and_intent()
          |> Map.merge(%{target_group: Policy.github_admin_group(), github_login: login})
          |> validate_intent()
        else
          {:error, {:invalid_github_login, login}}
        end

      _ ->
        {:error, :github_usage}
    end
  end

  defp parse_github_slash(_), do: {:error, :github_usage}

  defp parse_duration_and_intent(text) do
    with [maybe_duration, rest] <- String.split(text, ~r/\s+/, parts: 2),
         {:ok, seconds} <- parse_duration(maybe_duration) do
      %{ttl: seconds, intent: String.trim(rest)}
    else
      _ -> %{ttl: Approvals.default_ttl_seconds(), intent: String.trim(text)}
    end
  end

  defp validate_intent(%{intent: intent} = parsed) when byte_size(intent) >= 5,
    do: {:ok, parsed}

  defp validate_intent(_parsed), do: {:error, :intent_too_short}

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

  # The envs an elevation still means something for. Staging's write
  # tier rides on every engineering identity already (see
  # `TuistOps.JIT.Policy.always_write_env?/1`), so elevating it would
  # grant nothing while still pulling a second human into an
  # approval — the command rejects it with an explanation instead.
  defp elevatable_envs, do: Enum.reject(@valid_envs, &Policy.always_write_env?/1)

  defp human_error({:invalid_env, "github"}),
    do: "GitHub organization admin has its own command: #{github_usage_message()}"

  defp human_error({:invalid_env, env}),
    do: "Unknown env `#{env}`. Use one of: #{Enum.join(elevatable_envs(), ", ")}."

  defp human_error({:always_write_env, env}),
    do:
      "`#{env}` is writable for everyone on the tailnet — no elevation needed. Just run `kubectl --context tuist-k8s-#{env} ...`."

  defp human_error(:misplaced_thread_flag),
    do:
      "Put `--thread <T-…>` right after the env, typed with two hyphens: `/elevate <env> --thread <T-…> [duration] <intent>`."

  defp human_error({:invalid_thread_id, thread_id}),
    do: "`#{thread_id}` isn't an Amp thread ID (expected `T-<uuid>`)."

  defp human_error({:invalid_github_login, login}),
    do: "`#{login}` isn't a valid GitHub login."

  defp human_error(:github_usage), do: github_usage_message()

  defp human_error({:github_not_member, login}),
    do: "`#{login}` isn't an active member of the GitHub organization."

  defp human_error({:github_already_admin, login}),
    do: "`#{login}` is already a GitHub organization admin — no elevation needed."

  defp human_error({:github_elevation_active, login}),
    do: "`#{login}` already has an active GitHub admin elevation."

  defp human_error({:github_promote_failed, :github_already_admin}),
    do: "The GitHub account is already an organization admin."

  defp human_error({:github_promote_failed, :github_not_member}),
    do: "The GitHub account is no longer an active organization member."

  defp human_error({:github_promote_failed, reason}),
    do: "Promoting the GitHub account failed: #{github_api_error(reason)}"

  defp human_error({:github_api_failed, reason}),
    do: "Checking the GitHub account failed: #{github_api_error(reason)}"

  defp human_error(:missing_intent), do: usage_message()
  defp human_error(:missing_text), do: usage_message()
  defp human_error(:intent_too_short), do: "Intent must be at least 5 characters."
  defp human_error(reason), do: "Internal error: #{inspect(reason)}"

  defp usage_message do
    "Usage: `/elevate <env> [duration] <intent>` where env is one of #{Enum.join(elevatable_envs(), ", ")}. Duration is e.g. `15m` or `1h` (default #{div(Approvals.default_ttl_seconds(), 60)}m, max #{div(Approvals.max_ttl_seconds(), 60)}m). Intent should describe what you're going to do. Add `--thread <T-…>` after the env to elevate one of your own Amp orb threads instead of yourself. For GitHub organization admin, use `/elevate-github`."
  end

  defp github_api_error({:github_status, 403, body}),
    do:
      "GitHub returned 403 (#{github_message(body)}). The Tuist Ops GitHub App needs the organization Members permission with read and write access."

  defp github_api_error({:github_status, status, body}),
    do: "GitHub returned #{status} (#{github_message(body)})."

  defp github_api_error({:github_app_token, _reason}),
    do: "couldn't authenticate as the Tuist Ops GitHub App."

  defp github_api_error(reason), do: inspect(reason)

  defp github_message(%{"message" => message}) when is_binary(message), do: message
  defp github_message(body), do: inspect(body)

  defp github_usage_message do
    "Usage: `/elevate-github <login> [duration] <intent>` to make a GitHub account an organization admin. Duration is e.g. `15m` or `1h` (default #{div(Approvals.default_ttl_seconds(), 60)}m, max #{div(Approvals.max_ttl_seconds(), 60)}m). Intent should describe what you're going to do."
  end

  # Maps a Slack user id to the tailnet identity (email). Calls
  # Slack `users.info` which requires the bot app to hold the
  # `users:read` + `users:read.email` scopes. Assumes Slack
  # workspace email == tailnet login email, which is true for our
  # team (everyone uses tuist.dev for both). Failures return nil
  # so the caller can reject the request rather than mutate state
  # for a phantom identity.
  defp slack_user_to_email(slack_user_id) when is_binary(slack_user_id) do
    case SlackClient.user_email(slack_user_id) do
      {:ok, email} ->
        email

      {:error, reason} ->
        Logger.warning(
          "tuist_ops: failed to resolve Slack user #{slack_user_id} email: #{inspect(reason)}"
        )

        nil
    end
  end

  defp slack_user_to_email(_), do: nil

  defp approvals_channel do
    Environment.approvals_channel_id() || "#eng-ops"
  end
end
