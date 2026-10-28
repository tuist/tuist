defmodule Atlas.Accounts.POCs.Notifier do
  @moduledoc """
  Delivers the two out-of-band messages needed by the POC access flow:

  1. A verification email to the requester so we can prove they own the
     address they typed.
  2. A Slack message to the operator channel with `Approve` / `Deny`
     buttons so a human decides whether to grant access.

  Both channels degrade gracefully: if Slack is not configured, ops
  won't be notified but the request row still exists and can be approved
  from the dashboard. If the mailer bounces, the request row still
  exists so the visitor can try again.
  """

  import Swoosh.Email

  alias Atlas.Accounts.POCs.AccessRequest
  alias Atlas.Accounts.POCs.POC
  alias Atlas.Accounts.POCs.VerificationEmail
  alias Atlas.Mailer
  alias Atlas.Slack
  alias Atlas.Slack.API, as: SlackAPI
  alias Atlas.Slack.Channel
  alias AtlasWeb.Endpoint

  require Logger

  @from_email "no-reply@tuist.dev"
  @from_name "Tuist"

  def send_verification_email(%POC{} = poc, %AccessRequest{} = request, plaintext_token) do
    url = verification_url(poc, request, plaintext_token)
    subject = "Verify your email to open the #{brand_label(poc)} brief"

    text_body = """
    You (or someone using your email) asked to open the #{brand_label(poc)} POC brief on Tuist.

    Confirm the request by clicking the link below within 15 minutes:

    #{url}

    Once you confirm, the Tuist team will grant access. You will not need to
    confirm again from this browser for the next 30 days.

    If you did not request this, you can safely ignore this email.
    """

    html_body = VerificationEmail.render(brand_label(poc), url)

    new()
    |> from({@from_name, @from_email})
    |> to(request.email)
    |> subject(subject)
    |> text_body(text_body)
    |> html_body(html_body)
    |> Mailer.deliver()
  end

  def send_slack_request(%POC{} = poc, %AccessRequest{} = request) do
    channel = ops_channel_id()

    if is_nil(channel) do
      Logger.info("POC Slack notifications not configured, skipping request notification")
      {:ok, :skipped}
    else
      blocks = request_blocks(poc, request)
      text = "#{request.email} is requesting access to #{poc.title}"

      case SlackAPI.post_message(:company, channel, text, blocks) do
        {:ok, %{"ts" => ts}} -> {:ok, {channel, ts}}
        {:ok, _other} -> {:ok, :sent}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # Re-renders the Slack message once the request state changes so the ops
  # thread reflects the current status (email confirmed, approved, denied,
  # revoked).
  def refresh_slack_message(%POC{} = _poc, %AccessRequest{slack_channel_id: nil}), do: {:ok, :no_message}

  def refresh_slack_message(%POC{} = poc, %AccessRequest{} = request) do
    blocks = request_blocks(poc, request)
    text = "#{request.email} · access request · #{AccessRequest.status(request)}"

    SlackAPI.update_message(:company, request.slack_channel_id, request.slack_message_ts, text, blocks)
  end

  defp request_blocks(poc, request) do
    [
      section_block(header_text(poc, request)),
      section_block(status_line(request))
    ]
    |> maybe_append_metadata(poc, request)
    |> maybe_append_action_buttons(request)
  end

  defp header_text(poc, request) do
    "*POC access request*\n<mailto:#{request.email}|#{request.email}> is asking to open *#{poc.title}*."
  end

  defp status_line(request) do
    case AccessRequest.status(request) do
      :pending -> ":hourglass_flowing_sand: Waiting on the visitor to confirm their email."
      :awaiting_approval -> ":email: Email confirmed. Approve to let them in."
      :awaiting_email -> ":white_check_mark: Approved. Waiting on the visitor to confirm their email."
      :granted -> ":unlock: Access granted."
      :denied -> ":no_entry_sign: Denied."
      :revoked -> ":lock: Revoked."
    end
  end

  defp maybe_append_metadata(blocks, poc, request) do
    metadata =
      [
        {"Account", poc.account && poc.account.name},
        {"IP", request.requester_ip},
        {"User agent", request.requester_user_agent}
      ]
      |> Enum.filter(fn {_k, v} -> is_binary(v) and v != "" end)
      |> Enum.map_join("\n", fn {k, v} -> "*#{k}:* #{v}" end)

    if metadata == "", do: blocks, else: blocks ++ [section_block(metadata)]
  end

  defp maybe_append_action_buttons(blocks, request) do
    if AccessRequest.status(request) in [:pending, :awaiting_approval] do
      blocks ++ [action_buttons(request)]
    else
      blocks
    end
  end

  defp section_block(text) do
    %{"type" => "section", "text" => %{"type" => "mrkdwn", "text" => text}}
  end

  defp action_buttons(request) do
    %{
      "type" => "actions",
      "elements" => [
        action_button("Approve", "primary", "poc_access:approve:" <> request.id, request.id),
        action_button("Deny", "danger", "poc_access:deny:" <> request.id, request.id)
      ]
    }
  end

  defp action_button(label, style, action_id, value) do
    %{
      "type" => "button",
      "style" => style,
      "text" => %{"type" => "plain_text", "text" => label},
      "action_id" => action_id,
      "value" => value
    }
  end

  defp verification_url(poc, request, plaintext_token) do
    Endpoint.url() <>
      "/p/pocs/#{poc.public_token}/verify?" <>
      URI.encode_query(%{"request_id" => request.id, "token" => plaintext_token})
  end

  defp brand_label(%POC{account: %{name: name}}) when is_binary(name) and name != "", do: name
  defp brand_label(%POC{title: title}), do: title

  # POC access requests are posted to #customers by default because that is
  # where account owners already track engagement with the account. The env
  # var stays as an escape hatch for staging or one-off overrides. When
  # neither is set (bot has never seen the channel, no override configured),
  # we skip the Slack ping and operators approve from the Atlas dashboard.
  @default_ops_channel_name "customers"

  defp ops_channel_id do
    case System.get_env("ATLAS_POC_ACCESS_SLACK_CHANNEL_ID") do
      id when is_binary(id) and id != "" ->
        id

      _ ->
        case Slack.find_channel_by_name(:company, @default_ops_channel_name) do
          %Channel{channel_id: channel_id} -> channel_id
          _ -> nil
        end
    end
  end
end
