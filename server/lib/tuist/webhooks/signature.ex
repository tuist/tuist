defmodule Tuist.Webhooks.Signature do
  @moduledoc """
  HMAC-SHA256 signing for outgoing automation webhooks, following Stripe's
  scheme.

  The signed string is `"\#{unix_timestamp}.\#{raw_json_payload}"`. The header
  value is `"t=\#{timestamp},v1=\#{hex_signature}"`. Consumers verify by
  recomputing the HMAC over the same string and comparing in constant time;
  they should reject anything older than `tolerance_seconds` (default 5
  minutes) to prevent replay.
  """

  @default_tolerance_seconds 300
  @scheme "v1"

  @doc """
  Returns the signature header value for `payload` signed with `secret` at
  `timestamp` (Unix seconds).
  """
  def sign(payload, secret, timestamp) when is_binary(payload) and is_binary(secret) and is_integer(timestamp) do
    signed_payload = "#{timestamp}.#{payload}"
    digest = :crypto.mac(:hmac, :sha256, secret, signed_payload)
    "t=#{timestamp},#{@scheme}=#{Base.encode16(digest, case: :lower)}"
  end

  @doc """
  Verifies `signature_header` against `payload` and `secret`. Returns `:ok`
  or `{:error, reason}`. `:tolerance_seconds` and `:now` (Unix seconds) can
  be overridden for testing.
  """
  def verify(payload, signature_header, secret, opts \\ []) do
    tolerance = Keyword.get(opts, :tolerance_seconds, @default_tolerance_seconds)
    now = Keyword.get(opts, :now, System.system_time(:second))

    with {:ok, timestamp, sig} <- parse_header(signature_header),
         :ok <- check_timestamp(timestamp, now, tolerance) do
      compare(payload, timestamp, sig, secret)
    end
  end

  defp parse_header(header) when is_binary(header) do
    parts =
      header
      |> String.split(",", trim: true)
      |> Enum.map(&String.split(&1, "=", parts: 2))
      |> Enum.reduce(%{}, fn
        [k, v], acc -> Map.put(acc, k, v)
        _, acc -> acc
      end)

    with {:ok, ts_string} <- Map.fetch(parts, "t"),
         {:ok, sig} <- Map.fetch(parts, @scheme),
         {ts, ""} <- Integer.parse(ts_string) do
      {:ok, ts, sig}
    else
      _ -> {:error, :invalid_header}
    end
  end

  defp parse_header(_), do: {:error, :invalid_header}

  defp check_timestamp(timestamp, now, tolerance) do
    if abs(now - timestamp) <= tolerance do
      :ok
    else
      {:error, :timestamp_outside_tolerance}
    end
  end

  defp compare(payload, timestamp, sig, secret) do
    expected = :crypto.mac(:hmac, :sha256, secret, "#{timestamp}.#{payload}")

    with {:ok, decoded} <- decode(sig),
         true <- byte_size(decoded) == byte_size(expected),
         true <- :crypto.hash_equals(expected, decoded) do
      :ok
    else
      _ -> {:error, :signature_mismatch}
    end
  end

  defp decode(sig) do
    case Base.decode16(sig, case: :mixed) do
      {:ok, bin} -> {:ok, bin}
      :error -> :error
    end
  end

  @doc """
  Generates a fresh signing secret — 32 random bytes encoded as a
  `tuist_webhook_`-prefixed base64url string.

  Matches the `tuist_<scope>_<random>` convention used by other tokens
  in this codebase (project tokens, SCIM tokens, account tokens).
  """
  def generate_secret do
    "tuist_webhook_" <> (32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false))
  end
end
