defmodule Atlas.Inbox.Dkim.Resolver do
  @moduledoc """
  DNS seam for DKIM public-key retrieval.

  Kept as its own module so tests can stub it with Mimic instead of doing real
  DNS lookups (and without mutating global state).
  """

  require Logger

  @doc """
  Looks up the DKIM public keys published at `selector._domainkey.domain`.

  Returns a list of `%{key_type: :rsa | :ed25519, der: binary}` where `der` is
  the base64-decoded `p=` value (a SubjectPublicKeyInfo DER for RSA, or the raw
  32-byte key for Ed25519). Returns `[]` when the record is missing, revoked
  (`p=` empty), or malformed.
  """
  def public_keys(selector, domain) when is_binary(selector) and is_binary(domain) do
    name = String.to_charlist("#{selector}._domainkey.#{domain}")

    name
    |> :inet_res.lookup(:in, :txt)
    |> Enum.map(&join_txt/1)
    |> Enum.flat_map(&parse_key/1)
  rescue
    error ->
      # A missing record returns [] normally (no exception); reaching here means
      # the lookup itself failed, which operators should see.
      Logger.warning("DKIM DNS lookup failed for #{selector}._domainkey.#{domain}: #{inspect(error)}")
      []
  catch
    kind, reason ->
      Logger.warning("DKIM DNS lookup failed for #{selector}._domainkey.#{domain}: #{inspect({kind, reason})}")

      []
  end

  defp join_txt(parts) when is_list(parts) do
    Enum.map_join(parts, "", &to_string/1)
  end

  defp join_txt(part), do: to_string(part)

  defp parse_key(txt) do
    tags =
      txt
      |> String.split(";", trim: true)
      |> Enum.flat_map(fn pair ->
        case String.split(pair, "=", parts: 2) do
          [k, v] -> [{k |> String.trim() |> String.downcase(), String.trim(v)}]
          _ -> []
        end
      end)
      |> Map.new()

    key_type =
      case Map.get(tags, "k", "rsa") do
        "ed25519" -> :ed25519
        _ -> :rsa
      end

    case decode_p(Map.get(tags, "p")) do
      {:ok, der} -> [%{key_type: key_type, der: der}]
      :error -> []
    end
  end

  defp decode_p(nil), do: :error
  defp decode_p(""), do: :error

  defp decode_p(p) do
    p
    |> String.replace(~r/\s/, "")
    |> Base.decode64()
    |> case do
      {:ok, der} when byte_size(der) > 0 -> {:ok, der}
      _ -> :error
    end
  end
end
