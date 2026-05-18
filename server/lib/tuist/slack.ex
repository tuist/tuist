defmodule Tuist.Slack do
  @moduledoc ~S"""
  This module provides an API to interact with the Slack API
  """

  import Ecto.Query

  alias Tuist.Alerts.Alert
  alias Tuist.Alerts.AlertRule
  alias Tuist.Environment
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Slack.Client
  alias Tuist.Slack.Installation
  alias Tuist.Utilities.ByteFormatter
  alias Tuist.Utilities.DateFormatter

  @api_url "https://slack.com/api/chat.postMessage"

  def create_installation(attrs) do
    result =
      %Installation{}
      |> Installation.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, installation} ->
        broadcast_slack_installation_change(installation.account_id, :connected)
        {:ok, installation}

      error ->
        error
    end
  end

  def update_installation(installation, attrs) do
    installation
    |> Installation.changeset(attrs)
    |> Repo.update()
  end

  def delete_installation(%Installation{account_id: account_id} = installation) do
    result =
      Ecto.Multi.new()
      |> Ecto.Multi.update_all(:clear_slack_fields, clear_project_slack_fields_query(account_id), [])
      |> Ecto.Multi.update_all(
        :clear_alert_rule_slack_fields,
        clear_alert_rule_slack_fields_query(account_id),
        []
      )
      |> Ecto.Multi.delete(:delete_installation, installation)
      |> Repo.transaction()

    case result do
      {:ok, %{delete_installation: deleted_installation}} ->
        broadcast_slack_installation_change(account_id, :disconnected)
        {:ok, deleted_installation}

      {:error, _operation, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp broadcast_slack_installation_change(account_id, status) do
    Tuist.PubSub.broadcast(
      %{status: status},
      slack_installation_topic(account_id),
      :slack_installation_changed
    )
  end

  def slack_installation_topic(account_id), do: "slack_installation:#{account_id}"

  # Only clear destinations that still rely on the bot-token fallback.
  # Destinations that already migrated to a per-channel webhook keep working
  # independently of the legacy installation we're tearing down.
  defp clear_project_slack_fields_query(account_id) do
    from(p in Project,
      where: p.account_id == ^account_id,
      update: [
        set: [
          slack_channel_id:
            fragment(
              "CASE WHEN ? IS NULL THEN NULL ELSE ? END",
              p.slack_webhook_url,
              p.slack_channel_id
            ),
          slack_channel_name:
            fragment(
              "CASE WHEN ? IS NULL THEN NULL ELSE ? END",
              p.slack_webhook_url,
              p.slack_channel_name
            ),
          flaky_test_alerts_slack_channel_id:
            fragment(
              "CASE WHEN ? IS NULL THEN NULL ELSE ? END",
              p.flaky_test_alerts_slack_webhook_url,
              p.flaky_test_alerts_slack_channel_id
            ),
          flaky_test_alerts_slack_channel_name:
            fragment(
              "CASE WHEN ? IS NULL THEN NULL ELSE ? END",
              p.flaky_test_alerts_slack_webhook_url,
              p.flaky_test_alerts_slack_channel_name
            )
        ]
      ]
    )
  end

  defp clear_alert_rule_slack_fields_query(account_id) do
    from(ar in AlertRule,
      join: p in Project,
      on: ar.project_id == p.id,
      where: p.account_id == ^account_id,
      where: is_nil(ar.slack_webhook_url),
      update: [
        set: [
          slack_channel_id: nil,
          slack_channel_name: nil
        ]
      ]
    )
  end

  def generate_state_token(account_id) do
    Phoenix.Token.sign(TuistWeb.Endpoint, "slack_state", %{
      type: :account_installation,
      account_id: account_id
    })
  end

  def generate_channel_selection_token(project_id, account_id) do
    Phoenix.Token.sign(TuistWeb.Endpoint, "slack_state", %{
      type: :channel_selection,
      project_id: project_id,
      account_id: account_id
    })
  end

  def generate_alert_channel_selection_token(account_id, opts \\ []) do
    payload = %{
      type: :alert_channel_selection,
      account_id: account_id
    }

    payload =
      case Keyword.get(opts, :alert_rule_id) do
        nil -> payload
        alert_rule_id -> Map.put(payload, :alert_rule_id, alert_rule_id)
      end

    Phoenix.Token.sign(TuistWeb.Endpoint, "slack_state", payload)
  end

  def generate_flaky_alert_channel_selection_token(project_id, account_id) do
    Phoenix.Token.sign(TuistWeb.Endpoint, "slack_state", %{
      type: :flaky_alert_channel_selection,
      project_id: project_id,
      account_id: account_id
    })
  end

  def verify_state_token(token) do
    token_max_age_seconds = 600
    Phoenix.Token.verify(TuistWeb.Endpoint, "slack_state", token, max_age: token_max_age_seconds)
  end

  @channel_result_namespace "slack_channel_result"
  @channel_result_max_age_seconds 600
  @slack_webhook_prefix "https://hooks.slack.com/services/"

  @doc """
  Encrypts a `{channel_id, channel_name, webhook_url}` tuple coming back
  from the Slack OAuth callback so a LiveView can later verify the values
  came from us. The token is `Phoenix.Token.encrypt/4`-encrypted (not just
  signed) because the payload includes the webhook URL, which is a bearer
  credential — a signed-only token would be readable by anyone with access
  to the page that renders it.

  Returns `{:error, :invalid_webhook_url}` if the URL doesn't look like a
  real Slack webhook — a small belt-and-suspenders check on top of the
  encryption.
  """
  def sign_channel_result(%{webhook_url: webhook_url} = payload) when is_binary(webhook_url) do
    if slack_webhook_url?(webhook_url) do
      {:ok, Phoenix.Token.encrypt(TuistWeb.Endpoint, @channel_result_namespace, payload)}
    else
      {:error, :invalid_webhook_url}
    end
  end

  @doc """
  Decrypts a token produced by `sign_channel_result/1`. Re-checks the
  webhook URL against the Slack host allowlist after decoding so a stolen
  token can't smuggle a non-Slack URL through.
  """
  def verify_channel_result(token) when is_binary(token) do
    case Phoenix.Token.decrypt(TuistWeb.Endpoint, @channel_result_namespace, token,
           max_age: @channel_result_max_age_seconds
         ) do
      {:ok, %{webhook_url: webhook_url} = payload} ->
        if slack_webhook_url?(webhook_url), do: {:ok, payload}, else: {:error, :invalid_webhook_url}

      {:ok, _other} ->
        {:error, :invalid}

      {:error, _reason} = error ->
        error
    end
  end

  def verify_channel_result(_), do: {:error, :invalid}

  @doc """
  Returns true when the URL is a Slack incoming-webhook URL.
  """
  def slack_webhook_url?(url) when is_binary(url), do: String.starts_with?(url, @slack_webhook_prefix)
  def slack_webhook_url?(_), do: false

  @doc """
  Encrypts a Slack webhook URL for storage inside JSON columns (e.g.
  automation action payloads), where Cloak's Ecto types cannot apply.

  The result is base64-encoded ciphertext. Callers MUST validate the URL
  with `slack_webhook_url?/1` before encrypting.
  """
  def encrypt_webhook_url(url) when is_binary(url) do
    if slack_webhook_url?(url) do
      {:ok, ciphertext} = Tuist.Vault.encrypt(url)
      {:ok, Base.encode64(ciphertext)}
    else
      {:error, :invalid_webhook_url}
    end
  end

  @doc """
  Decrypts a webhook URL produced by `encrypt_webhook_url/1`.
  """
  def decrypt_webhook_url(encoded) when is_binary(encoded) do
    with {:ok, ciphertext} <- Base.decode64(encoded),
         {:ok, plaintext} <- Tuist.Vault.decrypt(ciphertext),
         true <- slack_webhook_url?(plaintext) do
      {:ok, plaintext}
    else
      _ -> {:error, :invalid_webhook_url}
    end
  end

  def decrypt_webhook_url(_), do: {:error, :invalid_webhook_url}

  def send_message(blocks, opts \\ []) do
    if Environment.tuist_hosted?() and Environment.prod?() do
      token = Environment.slack_tuist_token()

      channel =
        Keyword.get(
          opts,
          :channel,
          if(Environment.prod?(), do: "#notifications", else: "#notifications-non-prod")
        )

      headers = [
        {"Authorization", "Bearer #{token}"},
        {"Content-Type", "application/json"}
      ]

      body = Jason.encode!(%{channel: channel, blocks: blocks, unfurl_links: false, unfurl_media: false})

      response =
        @api_url
        |> Req.post(headers: headers, body: body)
        |> handle_response()

      case response do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}) do
    {:ok, body}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, "Unexpected status code: #{status}. Body: #{Jason.encode!(body)}"}
  end

  defp handle_response({:error, reason}) do
    {:error, "Request failed: #{inspect(reason)}"}
  end

  @doc """
  Sends an alert notification to Slack.

  Prefers the per-channel `slack_webhook_url`. Destinations created before
  the webhook flow existed fall back to `chat.postMessage` with the
  account-level bot token until the user re-selects the channel.
  """
  def send_alert(%Alert{} = alert) do
    alert = Repo.preload(alert, alert_rule: [project: [account: :slack_installation]])

    %Alert{
      alert_rule: %{
        slack_webhook_url: webhook_url,
        slack_channel_id: channel_id,
        project: %{name: project_name, account: %{name: account_name} = account}
      }
    } = alert

    blocks = build_alert_blocks(alert, account_name, project_name)
    deliver(webhook_url, account.slack_installation, channel_id, blocks)
  end

  defp deliver(webhook_url, _installation, _channel_id, blocks) when is_binary(webhook_url) and webhook_url != "" do
    Client.post_to_webhook(webhook_url, blocks)
  end

  defp deliver(_webhook_url, %Installation{access_token: token}, channel_id, blocks)
       when is_binary(token) and is_binary(channel_id) do
    Client.post_message(token, channel_id, blocks)
  end

  defp deliver(_webhook_url, _installation, _channel_id, _blocks), do: :ok

  defp build_alert_blocks(alert, account_name, project_name) do
    [
      alert_header_block(alert),
      alert_context_block(alert),
      alert_divider_block(),
      alert_metric_block(alert),
      alert_footer_block(alert, account_name, project_name)
    ]
  end

  defp alert_header_block(%Alert{alert_rule: alert_rule}) do
    emoji = alert_category_emoji(alert_rule.category)
    title = alert_title(alert_rule)

    %{
      type: "header",
      text: %{
        type: "plain_text",
        text: "#{emoji} Alert: #{title}"
      }
    }
  end

  defp alert_context_block(%Alert{inserted_at: triggered_at}) do
    ts = DateTime.to_unix(triggered_at)
    fallback = Calendar.strftime(triggered_at, "%b %d, %H:%M")

    %{
      type: "context",
      elements: [
        %{type: "mrkdwn", text: "Triggered at <!date^#{ts}^{date_short} {time}|#{fallback}>"}
      ]
    }
  end

  defp alert_divider_block, do: %{type: "divider"}

  defp alert_metric_block(alert) do
    message = format_alert_message(alert)

    %{
      type: "section",
      text: %{
        type: "mrkdwn",
        text: message
      }
    }
  end

  defp alert_footer_block(
         %Alert{alert_rule: %{category: :bundle_size, bundle_name: bundle_name}},
         account_name,
         project_name
       ) do
    base_url = Environment.app_url()
    path = "#{base_url}/#{account_name}/#{project_name}/bundles"

    url =
      if bundle_name == "" do
        path
      else
        "#{path}?bundle-size-app=#{bundle_name}"
      end

    %{
      type: "context",
      elements: [
        %{
          type: "mrkdwn",
          text: "<#{url}|View bundles>"
        }
      ]
    }
  end

  defp alert_footer_block(
         %Alert{alert_rule: %{category: :build_run_duration, scheme: scheme}},
         account_name,
         project_name
       ) do
    base_url = Environment.app_url()
    path = "#{base_url}/#{account_name}/#{project_name}/builds"

    url =
      if scheme == "" do
        path
      else
        "#{path}?analytics-build-scheme=#{scheme}"
      end

    %{
      type: "context",
      elements: [
        %{
          type: "mrkdwn",
          text: "<#{url}|View builds>"
        }
      ]
    }
  end

  defp alert_footer_block(%Alert{alert_rule: %{category: :test_run_duration, scheme: scheme}}, account_name, project_name) do
    base_url = Environment.app_url()
    path = "#{base_url}/#{account_name}/#{project_name}/tests"

    url =
      if scheme == "" do
        path
      else
        "#{path}?analytics-test-scheme=#{scheme}"
      end

    %{
      type: "context",
      elements: [
        %{
          type: "mrkdwn",
          text: "<#{url}|View tests>"
        }
      ]
    }
  end

  defp alert_footer_block(%Alert{alert_rule: %{category: :cache_hit_rate}}, account_name, project_name) do
    base_url = Environment.app_url()

    %{
      type: "context",
      elements: [
        %{
          type: "mrkdwn",
          text: "<#{base_url}/#{account_name}/#{project_name}/xcode-cache|View cache>"
        }
      ]
    }
  end

  defp alert_category_emoji(:build_run_duration), do: ":hammer_and_wrench:"
  defp alert_category_emoji(:test_run_duration), do: ":test_tube:"
  defp alert_category_emoji(:cache_hit_rate), do: ":zap:"
  defp alert_category_emoji(:bundle_size), do: ":package:"

  defp alert_title(%{category: :build_run_duration, metric: metric, scheme: ""}),
    do: "Build Time #{alert_metric_label(metric)} Increased"

  defp alert_title(%{category: :build_run_duration, metric: metric, scheme: scheme}),
    do: "#{scheme} Build Time #{alert_metric_label(metric)} Increased"

  defp alert_title(%{category: :test_run_duration, metric: metric, scheme: ""}),
    do: "Test Time #{alert_metric_label(metric)} Increased"

  defp alert_title(%{category: :test_run_duration, metric: metric, scheme: scheme}),
    do: "#{scheme} Test Time #{alert_metric_label(metric)} Increased"

  defp alert_title(%{category: :cache_hit_rate, metric: metric}),
    do: "Cache Hit Rate #{alert_metric_label(metric)} Decreased"

  defp alert_title(%{category: :bundle_size, bundle_name: ""}), do: "Bundle Size Increased"

  defp alert_title(%{category: :bundle_size, bundle_name: bundle_name}), do: "#{bundle_name} Bundle Size Increased"

  defp alert_metric_label(:p50), do: "p50"
  defp alert_metric_label(:p90), do: "p90"
  defp alert_metric_label(:p99), do: "p99"
  defp alert_metric_label(:average), do: "Average"
  defp alert_metric_label(nil), do: ""

  defp format_alert_message(%Alert{alert_rule: %{category: :build_run_duration, metric: metric, scheme: ""}} = alert) do
    deviation = calculate_increase_deviation(alert)

    "*Build time #{alert_metric_label(metric)} increased by #{deviation}%*\n" <>
      "Previous: #{format_alert_duration(alert.previous_value)}\n" <>
      "Current: #{format_alert_duration(alert.current_value)}"
  end

  defp format_alert_message(%Alert{alert_rule: %{category: :build_run_duration, metric: metric, scheme: scheme}} = alert) do
    deviation = calculate_increase_deviation(alert)

    "*#{scheme} build time #{alert_metric_label(metric)} increased by #{deviation}%*\n" <>
      "Previous: #{format_alert_duration(alert.previous_value)}\n" <>
      "Current: #{format_alert_duration(alert.current_value)}"
  end

  defp format_alert_message(%Alert{alert_rule: %{category: :test_run_duration, metric: metric, scheme: ""}} = alert) do
    deviation = calculate_increase_deviation(alert)

    "*Test time #{alert_metric_label(metric)} increased by #{deviation}%*\n" <>
      "Previous: #{format_alert_duration(alert.previous_value)}\n" <>
      "Current: #{format_alert_duration(alert.current_value)}"
  end

  defp format_alert_message(%Alert{alert_rule: %{category: :test_run_duration, metric: metric, scheme: scheme}} = alert) do
    deviation = calculate_increase_deviation(alert)

    "*#{scheme} test time #{alert_metric_label(metric)} increased by #{deviation}%*\n" <>
      "Previous: #{format_alert_duration(alert.previous_value)}\n" <>
      "Current: #{format_alert_duration(alert.current_value)}"
  end

  defp format_alert_message(%Alert{alert_rule: %{category: :cache_hit_rate, metric: metric}} = alert) do
    deviation = calculate_decrease_deviation(alert)

    "*Cache hit rate #{alert_metric_label(metric)} decreased by #{deviation}%*\n" <>
      "Previous: #{format_alert_percentage(alert.previous_value)}\n" <>
      "Current: #{format_alert_percentage(alert.current_value)}"
  end

  defp format_alert_message(%Alert{alert_rule: %{category: :bundle_size, metric: metric, bundle_name: ""}} = alert) do
    deviation = calculate_increase_deviation(alert)

    "*Bundle #{bundle_size_metric_label(metric)} increased by #{deviation}%*\n" <>
      "Previous: #{format_alert_bytes(alert.previous_value)}\n" <>
      "Current: #{format_alert_bytes(alert.current_value)}"
  end

  defp format_alert_message(
         %Alert{alert_rule: %{category: :bundle_size, metric: metric, bundle_name: bundle_name}} = alert
       ) do
    deviation = calculate_increase_deviation(alert)

    "*#{bundle_name} bundle #{bundle_size_metric_label(metric)} increased by #{deviation}%*\n" <>
      "Previous: #{format_alert_bytes(alert.previous_value)}\n" <>
      "Current: #{format_alert_bytes(alert.current_value)}"
  end

  defp calculate_increase_deviation(%Alert{current_value: current, previous_value: previous}) do
    Float.round((current - previous) / previous * 100, 1)
  end

  defp calculate_decrease_deviation(%Alert{current_value: current, previous_value: previous}) do
    Float.round((previous - current) / previous * 100, 1)
  end

  defp format_alert_duration(ms) when is_number(ms) do
    DateFormatter.format_duration_from_milliseconds(ms)
  end

  defp format_alert_percentage(rate) when is_number(rate) do
    "#{Float.round(rate * 100, 1)}%"
  end

  defp format_alert_bytes(value) when is_number(value) do
    ByteFormatter.format_bytes(round(value))
  end

  defp bundle_size_metric_label(:install_size), do: "install size"
  defp bundle_size_metric_label(:download_size), do: "download size"

  defp maybe_add_suite(details, nil), do: details
  defp maybe_add_suite(details, ""), do: details
  defp maybe_add_suite(details, suite_name), do: details ++ ["*Suite:* #{suite_name}"]

  @doc """
  Sends a flaky test alert notification to Slack using project-level settings.

  Prefers the per-channel `flaky_test_alerts_slack_webhook_url`; falls back to
  `chat.postMessage` with the account-level bot token for destinations
  configured before the webhook flow existed.
  """
  def send_flaky_test_alert(project, test_case, flaky_runs_count, was_auto_quarantined \\ false) do
    project = Repo.preload(project, account: :slack_installation)

    %Project{
      flaky_test_alerts_slack_webhook_url: webhook_url,
      flaky_test_alerts_slack_channel_id: channel_id,
      name: project_name,
      account: %{name: account_name} = account
    } = project

    blocks =
      build_flaky_test_alert_blocks(test_case, flaky_runs_count, account_name, project_name, was_auto_quarantined)

    deliver(webhook_url, account.slack_installation, channel_id, blocks)
  end

  defp build_flaky_test_alert_blocks(test_case, flaky_runs_count, account_name, project_name, was_auto_quarantined) do
    base_blocks = [
      flaky_test_alert_header_block(),
      flaky_test_alert_context_block(),
      alert_divider_block(),
      flaky_test_alert_test_case_block(test_case, account_name, project_name),
      flaky_test_alert_metric_block(flaky_runs_count)
    ]

    if was_auto_quarantined do
      base_blocks ++ [auto_quarantined_info_block()]
    else
      base_blocks
    end
  end

  defp flaky_test_alert_header_block do
    %{
      type: "header",
      text: %{
        type: "plain_text",
        text: ":warning: New flaky test detected"
      }
    }
  end

  defp flaky_test_alert_context_block do
    now = DateTime.utc_now()
    ts = DateTime.to_unix(now)
    fallback = Calendar.strftime(now, "%b %d, %H:%M")

    %{
      type: "context",
      elements: [
        %{type: "mrkdwn", text: "Triggered at <!date^#{ts}^{date_short} {time}|#{fallback}>"}
      ]
    }
  end

  defp flaky_test_alert_test_case_block(test_case, account_name, project_name) do
    base_url = Environment.app_url()
    test_case_url = "#{base_url}/#{account_name}/#{project_name}/tests/test-cases/#{test_case.id}"

    details =
      ["*Test:* <#{test_case_url}|#{test_case.name}>", "*Module:* #{test_case.module_name}"]
      |> maybe_add_suite(test_case.suite_name)
      |> Enum.join("\n")

    %{
      type: "section",
      text: %{
        type: "mrkdwn",
        text: details
      }
    }
  end

  defp flaky_test_alert_metric_block(flaky_runs_count) do
    runs_label = if flaky_runs_count == 1, do: "run", else: "runs"

    %{
      type: "section",
      text: %{
        type: "mrkdwn",
        text: "*#{flaky_runs_count} flaky #{runs_label} detected in the last 30 days*"
      }
    }
  end

  defp auto_quarantined_info_block do
    %{
      type: "context",
      elements: [
        %{type: "mrkdwn", text: ":no_entry_sign: _This test has been automatically quarantined_"}
      ]
    }
  end
end
