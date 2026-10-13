defmodule TuistWeb.Internal.KuraVolumeKeysController do
  @moduledoc """
  `POST /_internal/kura/volume-keys`: hands the `kura-volumes.tuist.dev` CSI
  node plugin the LUKS passphrase of a Kura data volume it is staging.

  ## Request

      Authorization: Bearer <ServiceAccount token>
      {"volume_id": "<PersistentVolume name>", "public_key": "<base64 X25519 public key>", "key_version": 1}

  The token is the node plugin's own pod-bound ServiceAccount token for the
  `kura-volume-keys.tuist.dev` audience. `public_key` is the raw 32-byte
  X25519 public key of a keypair the plugin generated for this request.
  `key_version` is optional: without it the account's active tenant key is
  used (and created on first use); with it, that version, active or retired.

  ## Response

      200 {"key_version": 1, "ephemeral_public_key": "<base64>", "nonce": "<base64>", "ciphertext": "<base64>"}

  The 32-byte passphrase is sealed to `public_key`:

    1. The server generates an ephemeral X25519 keypair; `ephemeral_public_key`
       is its raw 32-byte public key.
    2. `shared = X25519(server_ephemeral_private, client_public)`. An all-zero
       result is rejected as an invalid public key.
    3. `sealing_key = HKDF-SHA256(ikm = shared, salt = ephemeral_public_key || client_public_key,
       info = "kura-volume-key-transport/v1", length = 32)`.
    4. `ciphertext || tag = AES-256-GCM(sealing_key, nonce, plaintext = passphrase, aad = volume_id)`
       with a random 12-byte `nonce`; `ciphertext` carries the 32 encrypted
       bytes followed by the 16-byte tag.

  The plugin opens it with `X25519(client_private, ephemeral_public_key)` and
  the same derivation. All binary fields use standard base64 with padding.

  ## Errors

  Every error is `{"error": "<code>"}`:

    * 400 `invalid_volume_id`, `invalid_public_key`, `invalid_key_version`
    * 401 `unauthenticated`: the token is rejected, is not the node plugin's
      ServiceAccount, or is not bound to a node
    * 403 `forbidden`: the volume is not a `kura-volumes` volume pinned to the
      caller's node, or its claim is not a live Kura replica's
    * 404 `volume_not_found`, `key_version_not_found`
    * 429 `rate_limited`
    * 503 `unavailable`: no root keys are configured, or the Kubernetes API failed
  """
  use TuistWeb, :controller

  alias Tuist.Kura.VolumeKeys
  alias TuistWeb.RateLimit
  alias TuistWeb.RemoteIp

  require Logger

  @rate_limit 600

  def create(conn, params) do
    with {:allow, _count} <- rate_limit(conn),
         {:ok, key_version} <- key_version(params),
         {:ok, public_key} <- public_key(params),
         {:ok, sealed} <-
           VolumeKeys.issue(bearer_token(conn), params["volume_id"], public_key, key_version: key_version) do
      json(conn, %{
        key_version: sealed.key_version,
        ephemeral_public_key: Base.encode64(sealed.ephemeral_public_key),
        nonce: Base.encode64(sealed.nonce),
        ciphertext: Base.encode64(sealed.ciphertext)
      })
    else
      {:deny, _retry_after} -> error(conn, :too_many_requests, "rate_limited")
      {:error, reason} -> error_response(conn, reason)
    end
  end

  defp error_response(conn, reason) when reason in [:invalid_volume_id, :invalid_public_key, :invalid_key_version],
    do: error(conn, :bad_request, Atom.to_string(reason))

  defp error_response(conn, :unauthenticated), do: error(conn, :unauthorized, "unauthenticated")
  defp error_response(conn, :forbidden), do: error(conn, :forbidden, "forbidden")

  defp error_response(conn, reason) when reason in [:volume_not_found, :key_version_not_found],
    do: error(conn, :not_found, Atom.to_string(reason))

  defp error_response(conn, :root_keys_unavailable), do: error(conn, :service_unavailable, "unavailable")

  defp error_response(conn, {:kubernetes, reason}) do
    Logger.error("[Kura.VolumeKeys] Kubernetes API request failed: #{inspect(reason)}")
    error(conn, :service_unavailable, "unavailable")
  end

  defp error_response(conn, reason) do
    Logger.error("[Kura.VolumeKeys] failed to issue a volume key: #{inspect(reason)}")
    error(conn, :service_unavailable, "unavailable")
  end

  defp error(conn, status, code) do
    conn
    |> put_status(status)
    |> json(%{error: code})
  end

  defp rate_limit(conn) do
    RateLimit.hit("kura_volume_keys:ip:#{RemoteIp.get(conn)}", limit: @rate_limit, window: to_timeout(minute: 1))
  end

  defp key_version(%{"key_version" => version}) when is_integer(version) and version > 0, do: {:ok, version}
  defp key_version(%{"key_version" => nil}), do: {:ok, nil}
  defp key_version(%{"key_version" => _version}), do: {:error, :invalid_key_version}
  defp key_version(_params), do: {:ok, nil}

  defp public_key(%{"public_key" => encoded}) when is_binary(encoded) do
    case Base.decode64(encoded) do
      {:ok, <<_::binary-size(32)>> = public_key} -> {:ok, public_key}
      _ -> {:error, :invalid_public_key}
    end
  end

  defp public_key(_params), do: {:error, :invalid_public_key}

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token
      _ -> nil
    end
  end
end
