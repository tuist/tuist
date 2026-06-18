defmodule TuistOpsWeb.SlackController do
  @moduledoc """
  HTTP-side of the JIT elevation bot. Two POST endpoints, both
  Slack-signed (verified by `TuistOpsWeb.Plugs.SlackWebhookPlug`
  before the controller sees the request):

    * `/webhooks/slack/slash` — receives the `/elevate` slash
      command. Parses `<env> [duration] <intent...>` from the
      `text` field and creates a Request via
      `TuistOps.JIT.Approvals.request_elevation/1`. Responds
      ephemerally to the requester.

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
  alias TuistOps.Previews
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

  def slash(conn, %{"command" => "/preview"} = params) do
    preview_slash(conn, params)
  end

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
        Logger.warning("tuist_ops slash failed: #{inspect(reason)}")
        json(conn, %{response_type: "ephemeral", text: human_error(reason)})
    end
  end

  def slash(conn, _params) do
    json(conn, %{response_type: "ephemeral", text: usage_message()})
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

      "preview_delete" ->
        do_preview_delete(conn, value, user_slack_id, user_email, channel_id)

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

          {:error, :approver_not_authorized} ->
            SlackClient.ephemeral(
              channel_id,
              actor_slack_id,
              ":no_entry: Your Tailscale role doesn't allow approving this env. " <>
                "Production approvals require an Owner or Admin role; engineers can only approve staging and canary."
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
  # Previews
  # ----------------------------------------------------------------

  defp preview_slash(conn, %{"text" => raw_text} = params) do
    requester_slack_id = params["user_id"]
    requester_email = slack_user_to_email(requester_slack_id)
    channel_id = previews_channel()

    result =
      case parse_preview_slash(raw_text) do
        {:ok, :create, parsed} ->
          Previews.create(%{
            requester_email: requester_email,
            requester_slack_id: requester_slack_id,
            slack_channel_id: channel_id,
            slug: parsed.slug,
            ttl_seconds: parsed.ttl_seconds,
            ref_kind: parsed.ref_kind,
            ref_value: parsed.ref_value,
            reason: parsed.reason
          })

        {:ok, :delete, parsed} ->
          Previews.delete(%{
            requester_email: requester_email,
            requester_slack_id: requester_slack_id,
            slack_channel_id: channel_id,
            slug: parsed.slug,
            reason: parsed.reason
          })

        {:error, reason} ->
          {:error, reason}
      end

    case result do
      {:ok, _request} ->
        json(conn, %{
          response_type: "ephemeral",
          text: "Preview request posted to <##{channel_id}>."
        })

      {:error, reason} ->
        Logger.warning("tuist_ops preview slash failed: #{inspect(reason)}")
        json(conn, %{response_type: "ephemeral", text: preview_human_error(reason)})
    end
  end

  defp preview_slash(conn, _params) do
    json(conn, %{response_type: "ephemeral", text: preview_usage_message()})
  end

  defp do_preview_delete(conn, slug, actor_slack_id, actor_email, channel_id) do
    case Previews.delete(%{
           requester_email: actor_email,
           requester_slack_id: actor_slack_id,
           slack_channel_id: channel_id || previews_channel(),
           slug: slug,
           reason: "Delete requested from Slack"
         }) do
      {:ok, _request} ->
        send_resp(conn, 200, "")

      {:error, reason} ->
        SlackClient.ephemeral(
          channel_id,
          actor_slack_id,
          "Preview delete failed: #{preview_human_error(reason)}"
        )

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
            {:ok, seconds} ->
              {:ok, env, seconds, String.trim(rest)}

            :error ->
              {:ok, env, Approvals.default_ttl_seconds(),
               String.trim("#{maybe_duration} #{rest}")}
          end

        [env, rest] ->
          {:ok, env, Approvals.default_ttl_seconds(), String.trim(rest)}

        _ ->
          {:error, :missing_intent}
      end

    validate_intent(case_result)
  end

  defp parse_slash(_), do: {:error, :missing_text}

  defp validate_intent({:ok, env, ttl, intent}) when byte_size(intent) >= 5,
    do: {:ok, env, ttl, intent}

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

  defp human_error({:invalid_env, env}),
    do: "Unknown env `#{env}`. Use one of: #{Enum.join(@valid_envs, ", ")}."

  defp human_error(:missing_intent), do: usage_message()
  defp human_error(:missing_text), do: usage_message()
  defp human_error(:intent_too_short), do: "Intent must be at least 5 characters."
  defp human_error(reason), do: "Internal error: #{inspect(reason)}"

  defp usage_message do
    "Usage: `/elevate <env> [duration] <intent>` where env is one of #{Enum.join(@valid_envs, ", ")}. Duration is e.g. `15m` or `1h` (default #{div(Approvals.default_ttl_seconds(), 60)}m, max #{div(Approvals.max_ttl_seconds(), 60)}m). Intent should describe what you're going to do."
  end

  defp parse_preview_slash(text) when is_binary(text) do
    case String.split(String.trim(text), ~r/\s+/, trim: true) do
      ["create", slug | rest] ->
        parse_preview_create(slug, rest)

      ["delete", slug | rest] ->
        reason = rest |> Enum.join(" ") |> String.trim()

        with :ok <- validate_preview_slug(slug) do
          {:ok, :delete,
           %{
             slug: slug,
             reason: if(reason == "", do: "Delete requested from Slack", else: reason)
           }}
        end

      _ ->
        {:error, :preview_usage}
    end
  end

  defp parse_preview_slash(_), do: {:error, :preview_usage}

  defp parse_preview_create(slug, rest) do
    {opts, reason_tokens} = Enum.split_while(rest, &preview_option?/1)
    reason = reason_tokens |> Enum.join(" ") |> String.trim()

    with :ok <- validate_preview_slug(slug),
         :ok <- validate_preview_reason(reason),
         {:ok, ttl_seconds} <- preview_ttl(opts),
         {:ok, ref_kind, ref_value} <- preview_ref(opts) do
      {:ok, :create,
       %{
         slug: slug,
         ttl_seconds: ttl_seconds,
         ref_kind: ref_kind,
         ref_value: ref_value,
         reason: reason
       }}
    end
  end

  defp preview_option?(token) do
    Regex.match?(~r/^(\d+[mhd]|pr:\d+|sha:[0-9a-f]{7,40})$/, token)
  end

  defp validate_preview_slug(slug) do
    if Regex.match?(~r/^[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])?$/, slug) do
      :ok
    else
      {:error, :preview_bad_slug}
    end
  end

  defp validate_preview_reason(reason) do
    if byte_size(reason) >= 5, do: :ok, else: {:error, :preview_reason_too_short}
  end

  defp preview_ttl(opts) do
    opts
    |> Enum.find(&Regex.match?(~r/^\d+[mhd]$/, &1))
    |> case do
      nil -> {:ok, Previews.default_ttl_seconds()}
      value -> parse_preview_duration(value)
    end
  end

  defp parse_preview_duration(value) do
    case Regex.run(~r/^(\d+)([mhd])$/, value) do
      [_, count, unit] ->
        {count, ""} = Integer.parse(count)

        seconds =
          case unit do
            "m" -> count * 60
            "h" -> count * 3600
            "d" -> count * 86_400
          end

        {:ok, min(seconds, Previews.max_ttl_seconds())}

      _ ->
        {:error, :preview_bad_duration}
    end
  end

  defp preview_ref(opts) do
    refs = Enum.filter(opts, &Regex.match?(~r/^(pr:\d+|sha:[0-9a-f]{7,40})$/, &1))

    case refs do
      [] ->
        {:ok, nil, nil}

      [ref] ->
        [kind, value] = String.split(ref, ":", parts: 2)
        {:ok, kind, value}

      _ ->
        {:error, :preview_too_many_refs}
    end
  end

  defp preview_human_error(:preview_usage), do: preview_usage_message()

  defp preview_human_error(:preview_bad_slug),
    do:
      "Slug must be 1-40 characters of lowercase letters, numbers, and hyphens, starting and ending with a letter or number."

  defp preview_human_error(:preview_reason_too_short), do: "Reason must be at least 5 characters."

  defp preview_human_error(:preview_bad_duration),
    do: "Duration must look like `2h`, `30m`, or `1d`."

  defp preview_human_error(:preview_too_many_refs),
    do: "Provide at most one `pr:<number>` or `sha:<sha>`."

  defp preview_human_error(:already_exists),
    do:
      "A preview with that slug already exists. Delete it (`/preview delete <slug>`) before creating a new one for the same slug."

  defp preview_human_error(:not_found), do: "No preview with that slug exists."

  defp preview_human_error(reason), do: "Internal error: #{inspect(reason)}"

  defp preview_usage_message do
    "Usage: `/preview create <slug> [duration] [pr:<number>|sha:<sha>] <reason>` or `/preview delete <slug> [reason]`."
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

  defp previews_channel do
    Environment.previews_channel_id() || approvals_channel()
  end
end
