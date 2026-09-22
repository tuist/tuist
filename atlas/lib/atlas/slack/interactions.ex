defmodule Atlas.Slack.Interactions do
  @moduledoc """
  Handles Slack interactivity payloads.
  """

  alias Atlas.Accounts.POCs
  alias Atlas.Accounts.POCs.Notifier, as: POCNotifier
  alias Atlas.Audit
  alias Atlas.Briefs.ItemActions
  alias Atlas.Briefs.Notifier, as: BriefNotifier
  alias Atlas.GTM
  alias Atlas.GTM.Outreach.SlackNotifier
  alias Atlas.Nudges.SlackActions, as: NudgesSlackActions
  alias Atlas.Nudges.SlackNotifier, as: NudgesSlackNotifier
  alias Atlas.Outreach
  alias Atlas.Outreach.RecommendationNotifier
  alias Atlas.Slack
  alias Atlas.Slack.API
  alias Atlas.Slack.User
  alias Atlas.Users

  require Logger

  def handle_interaction(%{"type" => "block_actions", "actions" => actions} = payload, app_key) when is_list(actions) do
    actions
    |> Enum.find_value(:ignored, &handle_action(&1, payload, app_key))
    |> normalize_result()
  end

  def handle_interaction(_payload, _app_key), do: {:ok, "Slack action ignored."}

  defp handle_action(%{"action_id" => action_id, "value" => opportunity_id}, payload, app_key)
       when is_binary(action_id) and is_binary(opportunity_id) do
    case app_key do
      :company ->
        opts =
          payload
          |> notification_opts()
          |> Keyword.put(:slack_app, app_key)
          |> Keyword.put(:actor_email, actor_email(payload, app_key))

        result =
          Audit.with_context(slack_audit_context(payload), fn ->
            handle_company_action(action_id, opportunity_id, opts)
          end)

        case result do
          {:ok, %{message: message}} ->
            {:ok, message}

          {:error, reason} ->
            Logger.warning("Failed to handle Slack action #{action_id}: #{inspect(reason)}")
            {:error, action_error_message(reason)}

          :ignored ->
            false
        end

      _other ->
        false
    end
  end

  defp handle_action(_action, _payload, _app_key), do: false

  defp normalize_result(:ignored), do: {:ok, "Slack action ignored."}
  defp normalize_result(result), do: result

  defp handle_company_action(action_id, target_id, opts) do
    resolvers = [
      &brief_action/3,
      &recommendation_action/3,
      &gtm_opportunity_action/3,
      &poc_access_action/3,
      &nudge_action/3
    ]

    Enum.find_value(resolvers, &apply(&1, [action_id, target_id, opts])) || :ignored
  end

  defp brief_action(action_id, target_id, opts) do
    case BriefNotifier.parse_action_id(action_id) do
      {:ok, action} -> ItemActions.handle_slack_action(action, target_id, opts)
      :error -> nil
    end
  end

  defp recommendation_action(action_id, target_id, opts) do
    case RecommendationNotifier.parse_action_id(action_id) do
      {:ok, action} -> Outreach.handle_recommendation_slack_action(action, target_id, opts)
      :error -> nil
    end
  end

  defp gtm_opportunity_action(action_id, target_id, opts) do
    case SlackNotifier.parse_action_id(action_id) do
      {:ok, action} -> GTM.handle_gtm_opportunity_slack_action(action, target_id, opts)
      :error -> nil
    end
  end

  defp poc_access_action(action_id, _target_id, opts) do
    case parse_poc_access_action(action_id) do
      {:ok, action, request_id} -> handle_poc_access_action(action, request_id, opts)
      :error -> nil
    end
  end

  # The nudge dispatch used to be the innermost `:error` branch in the old
  # nested case; after the flattening rewrite it sits as the last resolver.
  # It returns nil (not `:ignored`) so the coordinator can fall through to the
  # shared `:ignored` sentinel at the end of `handle_company_action/3`.
  defp nudge_action(action_id, target_id, opts) do
    case NudgesSlackNotifier.parse_action_id(action_id) do
      {:ok, action} -> NudgesSlackActions.handle_slack_action(action, target_id, opts)
      :error -> nil
    end
  end

  defp parse_poc_access_action("poc_access:approve:" <> request_id), do: {:ok, :approve, request_id}
  defp parse_poc_access_action("poc_access:deny:" <> request_id), do: {:ok, :deny, request_id}
  defp parse_poc_access_action(_action_id), do: :error

  defp handle_poc_access_action(action, request_id, opts) do
    case Users.get_user_by_email(opts[:actor_email]) do
      nil ->
        {:error, :poc_access_actor_required}

      user ->
        apply_poc_access_action(action, request_id, user)
    end
  end

  defp apply_poc_access_action(:approve, request_id, user) do
    with {:ok, request} <- POCs.approve_access_request(request_id, user),
         %{} = poc <- POCs.get_poc(request.poc_id) do
      POCNotifier.refresh_slack_message(poc, request)
      {:ok, %{message: "Approved access for #{request.email}."}}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_poc_access_action(:deny, request_id, user) do
    with {:ok, request} <- POCs.deny_access_request(request_id, user),
         %{} = poc <- POCs.get_poc(request.poc_id) do
      POCNotifier.refresh_slack_message(poc, request)
      {:ok, %{message: "Denied access for #{request.email}."}}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp notification_opts(payload) do
    case get_in(payload, ["container", "channel_id"]) do
      channel_id when is_binary(channel_id) and channel_id != "" -> [slack_channel_id: channel_id]
      _channel_id -> []
    end
  end

  defp slack_audit_context(payload) do
    %{
      interface: "slack",
      actor_name: get_in(payload, ["user", "name"]),
      actor_email: get_in(payload, ["user", "profile", "email"])
    }
  end

  defp actor_email(payload, app_key) do
    case get_in(payload, ["user", "profile", "email"]) do
      email when is_binary(email) and email != "" -> email
      _email -> resolve_actor_email(app_key, get_in(payload, ["user", "id"]))
    end
  end

  defp resolve_actor_email(app_key, slack_user_id) when is_binary(slack_user_id) and slack_user_id != "" do
    case Slack.get_user(app_key, slack_user_id) do
      %User{email: email} when is_binary(email) and email != "" ->
        email

      _user ->
        with {:ok, profile} <- API.get_user_info(app_key, slack_user_id),
             {:ok, slack_user} <- Slack.upsert_user(app_key, profile),
             email when is_binary(email) and email != "" <- slack_user.email do
          email
        else
          _error -> nil
        end
    end
  end

  defp resolve_actor_email(_app_key, _slack_user_id), do: nil

  defp action_error_message(:not_found), do: "GTM opportunity not found."
  defp action_error_message(:brief_item_actor_required), do: "Atlas could not match your Slack email to a user."
  defp action_error_message(:brief_item_executive_required), do: "Leadership brief actions require an executive role."
  defp action_error_message(:unsupported_brief_action), do: "That brief action is not supported."
  defp action_error_message(:unsupported_action), do: "That outreach action is not supported."

  defp action_error_message(:outreach_recommendation_slack_channel_not_configured),
    do: "The outreach Slack channel is not configured."

  defp action_error_message(:apollo_api_key_not_configured), do: "Apollo is not configured."
  defp action_error_message(:apollo_organization_not_found), do: "Apollo could not resolve that company."

  defp action_error_message(:domain_required),
    do: "Apollo needs a company domain or a resolvable company name before it can find leaders."

  defp action_error_message(:gtm_outreach_slack_channel_not_configured), do: "GTM Slack channel is not configured."
  defp action_error_message(:nudge_not_found), do: "Nudge not found."
  defp action_error_message(:nudge_actor_required), do: "Atlas could not match your Slack email to a user."
  defp action_error_message(:nudge_scope_required), do: "Nudge actions require accounts:write scope."
  defp action_error_message(:unsupported_nudge_action), do: "That nudge action is not supported."
  defp action_error_message(:score_below_threshold), do: "Opportunity score is below the Slack notification threshold."
  defp action_error_message(:poc_access_actor_required), do: "Atlas could not match your Slack email to a user."
  defp action_error_message(:already_denied), do: "That POC access request was already denied."
  defp action_error_message(reason), do: "GTM action failed: #{inspect(reason)}"
end
