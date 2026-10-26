defmodule AtlasWeb.NativeLinks.Config do
  @moduledoc """
  Verified native app identities for universal and app links.

  Both lists are empty unless configured, and the association files are not served
  while their list is empty. The Android list must contain stable release-signing
  certificate fingerprints, never an ephemeral debug key.
  """

  @apple_app_id ~r/\A[A-Z0-9]{10}\.[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\z/
  @android_fingerprint ~r/\A[0-9A-F]{2}(:[0-9A-F]{2}){31}\z/

  def apple_app_ids, do: Keyword.get(config(), :apple_app_ids, [])

  def android_sha256_fingerprints, do: Keyword.get(config(), :android_sha256_fingerprints, [])

  @doc "The configured HTTPS origin for native links, or nil if the endpoint is not served over HTTPS."
  def origin do
    case URI.parse(AtlasWeb.Endpoint.url()) do
      %URI{scheme: "https", host: host, path: path, query: nil, fragment: nil, userinfo: nil} = uri
      when is_binary(host) and host != "" and path in [nil, "", "/"] ->
        URI.to_string(%{uri | path: nil})

      _uri ->
        nil
    end
  end

  # Pure parsing keeps runtime configuration testable without changing the
  # process-wide environment. Malformed explicit values fail at boot.
  def parse!(env) do
    [
      apple_app_ids: list!(env, "ATLAS_APPLE_APP_IDS", @apple_app_id, "Apple app IDs (TEAMID.bundle.id)"),
      android_sha256_fingerprints:
        list!(
          env,
          "ATLAS_ANDROID_APP_LINK_SHA256",
          @android_fingerprint,
          "uppercase colon-separated SHA-256 certificate fingerprints"
        )
    ]
  end

  defp list!(env, name, pattern, description) do
    env
    |> Map.get(name, "")
    |> String.trim()
    |> case do
      "" ->
        []

      value ->
        values = value |> String.split(",") |> Enum.map(&String.trim/1)

        if Enum.all?(values, &Regex.match?(pattern, &1)) do
          Enum.uniq(values)
        else
          raise "environment variable #{name} must be a comma-separated list of #{description}"
        end
    end
  end

  defp config, do: Application.get_env(:atlas, :native_links, [])
end
