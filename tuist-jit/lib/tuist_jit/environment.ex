defmodule TuistJit.Environment do
  @moduledoc """
  Runtime environment lookups for tuist-jit. Reads bot credentials,
  Slack channel ids, and Tailscale tailnet config from env vars
  populated by the ESO ExternalSecret in `infra/helm/tuist-jit/`.

  Centralised here so test code can stub a single module via Mimic
  rather than touching `System.get_env` directly.
  """

  def tailscale_client_id, do: System.get_env("TAILSCALE_CLIENT_ID")
  def tailscale_client_secret, do: System.get_env("TAILSCALE_CLIENT_SECRET")
  def tailscale_tailnet, do: System.get_env("TAILSCALE_TAILNET") || "-"

  def slack_signing_secret, do: System.get_env("SLACK_SIGNING_SECRET")
  def slack_bot_token, do: System.get_env("SLACK_BOT_TOKEN")
  def approvals_channel_id, do: System.get_env("SLACK_APPROVALS_CHANNEL_ID")
end
