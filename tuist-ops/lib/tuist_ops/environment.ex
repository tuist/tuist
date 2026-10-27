defmodule TuistOps.Environment do
  @moduledoc """
  Runtime environment lookups for tuist-ops. Reads bot credentials,
  Slack channel ids, and Tailscale tailnet config from env vars
  populated by the ESO ExternalSecret in `infra/helm/tuist-ops/`.

  Centralised here so test code can stub a single module via Mimic
  rather than touching `System.get_env` directly.
  """

  def tailscale_client_id, do: System.get_env("TAILSCALE_CLIENT_ID")
  def tailscale_client_secret, do: System.get_env("TAILSCALE_CLIENT_SECRET")
  def tailscale_tailnet, do: System.get_env("TAILSCALE_TAILNET") || "-"

  def slack_signing_secret, do: System.get_env("SLACK_SIGNING_SECRET")
  def slack_bot_token, do: System.get_env("SLACK_BOT_TOKEN")
  def approvals_channel_id, do: System.get_env("SLACK_APPROVALS_CHANNEL_ID")
  def previews_channel_id, do: System.get_env("SLACK_PREVIEWS_CHANNEL_ID")

  def github_app_id, do: System.get_env("GITHUB_APP_ID")
  def github_app_installation_id, do: System.get_env("GITHUB_APP_INSTALLATION_ID")
  def github_app_private_key, do: System.get_env("GITHUB_APP_PRIVATE_KEY")
  def github_repository, do: System.get_env("GITHUB_REPOSITORY") || "tuist/tuist"
  def github_workflow_ref, do: System.get_env("GITHUB_WORKFLOW_REF") || "main"

  def preview_workflow_id do
    System.get_env("PREVIEW_WORKFLOW_ID") || "preview-deploy.yml"
  end

  # --- Operator project-access grants -----------------------------------

  @doc """
  PEM-encoded Ed25519 private key used to sign operator access grant
  tokens. The customer server holds the matching public key and
  verifies offline. nil when unset (signing then raises — a missing
  key is a deploy bug, not a runtime fallback).
  """
  def project_access_signing_key, do: System.get_env("PROJECT_ACCESS_SIGNING_KEY")

  @doc """
  The `aud` claim stamped on grant tokens. The customer server pins
  this to reject a token minted for a different environment. Defaults
  to `"tuist-server"`; set `OPERATOR_GRANT_AUDIENCE` per env.
  """
  def operator_grant_audience, do: System.get_env("OPERATOR_GRANT_AUDIENCE") || "tuist-server"

  @doc """
  Allowed `return_to` origins for the redirect-back after a grant is
  minted. Prevents a signed admin token from being redirected to an
  attacker-controlled host. Comma-separated `scheme://host[:port]`
  entries in `PROJECT_ACCESS_RETURN_TO_ALLOWLIST`; defaults to the
  production app host.
  """
  def project_access_return_to_allowlist do
    case System.get_env("PROJECT_ACCESS_RETURN_TO_ALLOWLIST") do
      value when is_binary(value) and value != "" ->
        value |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

      _ ->
        ["https://tuist.dev"]
    end
  end

  @doc """
  Local-development fallback for the operator identity when there is
  no Pomerium in front of ops to set `X-Pomerium-Claim-Email`. nil in
  production, so a missing Pomerium header there means "no subject".
  """
  def dev_operator_email, do: System.get_env("TUIST_OPS_DEV_OPERATOR_EMAIL")

  @doc """
  Google Workspace domain a grant requester's identity must belong to.
  A defence-in-depth backstop on the verified Pomerium identity.
  Defaults to `"tuist.dev"`; set `OPERATOR_EMAIL_DOMAIN`.
  """
  def operator_email_domain, do: System.get_env("OPERATOR_EMAIL_DOMAIN") || "tuist.dev"

  @doc """
  PEM-encoded public key of Pomerium's JWT signing key. tuist-ops
  verifies the `X-Pomerium-Jwt-Assertion` ES256 signature offline with
  it, so a request that did NOT pass through Pomerium (e.g. a raw
  tailnet client forging `X-Pomerium-Claim-Email`) carries no usable
  identity. nil when unset — the operator HTML surface then has no
  verified identity and fails closed.
  """
  def pomerium_jwt_public_key, do: System.get_env("POMERIUM_JWT_PUBLIC_KEY")

  @doc """
  Expected `aud` on Pomerium's assertion — the public host of the
  operator surface, which Pomerium stamps per route. Defaults to
  `"ops.tuist.dev"`; set `POMERIUM_AUDIENCE`.
  """
  def pomerium_audience, do: System.get_env("POMERIUM_AUDIENCE") || "ops.tuist.dev"
end
