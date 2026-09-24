defmodule Atlas.Inbox.Dkim do
  @moduledoc """
  Minimal DKIM (RFC 6376) signature verification.

  `verified_domains/1` returns the set of signing domains (`d=`) whose
  DKIM-Signature cryptographically verifies against the key published in DNS:
  both the body hash and the RSA/Ed25519 signature must check out. A domain in
  that set means "this message really was signed by that domain", which is the
  anti-spoofing primitive `Atlas.Inbox` gates sender authorization on.

  Supported: rsa-sha256, rsa-sha1, ed25519-sha256; `simple` and `relaxed`
  canonicalization for both headers and body; the `l=` body-length tag. Unknown
  algorithms or unparseable signatures are skipped (a single verified signature
  is enough), so this is fail-closed: no verified signature means no domain.
  """

  alias Atlas.Inbox.Dkim.Resolver

  require Logger

  @doc """
  Returns the lowercased signing domains whose DKIM-Signature verifies.
  """
  def verified_domains(raw_email) when is_binary(raw_email) do
    {header_block, body} = split_message(normalize_crlf(raw_email))
    headers = parse_headers(header_block)

    headers
    |> Enum.filter(fn {name, _raw} -> String.downcase(String.trim(name)) == "dkim-signature" end)
    |> Enum.flat_map(fn {_name, raw} ->
      case verify_signature(raw, headers, body) do
        {:ok, domain} -> [domain]
        :error -> []
      end
    end)
    |> Enum.uniq()
  end

  def verified_domains(_raw_email), do: []

  # -- Signature verification --

  defp verify_signature(sig_header, headers, body) do
    tags = parse_tag_list(tag_value(sig_header))

    with domain when is_binary(domain) <- Map.get(tags, "d"),
         selector when is_binary(selector) <- Map.get(tags, "s"),
         {:ok, {sig_alg, hash_alg}} <- algorithm(Map.get(tags, "a")),
         {header_canon, body_canon} <- canonicalization(Map.get(tags, "c")),
         {:ok, signature} <- decode_b64(Map.get(tags, "b")),
         {:ok, expected_bh} <- decode_b64(Map.get(tags, "bh")),
         :ok <- check_body_hash(body, body_canon, hash_alg, Map.get(tags, "l"), expected_bh) do
      signed = signed_header_data(tags, sig_header, headers, header_canon)
      keys = Resolver.public_keys(selector, domain)

      if Enum.any?(keys, &valid_signature?(&1, sig_alg, hash_alg, signed, signature)) do
        {:ok, String.downcase(domain)}
      else
        :error
      end
    else
      _ -> :error
    end
  rescue
    error ->
      # Only unexpected crashes reach here; the normal "not verified" path is
      # the `else` clause above. Warn so a broken verifier is distinguishable
      # from legitimately unsigned mail.
      Logger.warning("DKIM verification crashed: #{inspect(error)}")
      :error
  end

  defp valid_signature?(%{key_type: :rsa, der: der}, :rsa, hash_alg, data, signature) do
    case rsa_public_key(der) do
      {:ok, key} -> :public_key.verify(data, hash_alg, signature, key)
      :error -> false
    end
  end

  defp valid_signature?(%{key_type: :ed25519, der: pub}, :ed25519, _hash_alg, data, signature)
       when byte_size(pub) == 32 do
    :crypto.verify(:eddsa, :none, data, signature, [pub, :ed25519])
  rescue
    _ -> false
  end

  defp valid_signature?(_key, _alg, _hash, _data, _sig), do: false

  defp rsa_public_key(der) do
    pem = :public_key.pem_encode([{:SubjectPublicKeyInfo, der, :not_encrypted}])

    case :public_key.pem_decode(pem) do
      [entry] -> {:ok, :public_key.pem_entry_decode(entry)}
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp check_body_hash(body, body_canon, hash_alg, length_tag, expected) do
    canonical =
      body
      |> canonicalize_body(body_canon)
      |> apply_body_length(length_tag)

    if :crypto.hash(hash_alg, canonical) == expected, do: :ok, else: :error
  end

  defp apply_body_length(body, nil), do: body
  defp apply_body_length(body, ""), do: body

  defp apply_body_length(body, length_tag) do
    case Integer.parse(length_tag) do
      {len, ""} when len >= 0 -> binary_part(body, 0, min(len, byte_size(body)))
      _ -> body
    end
  end

  # -- Signed header data assembly (RFC 6376 3.7) --

  defp signed_header_data(tags, sig_header, headers, header_canon) do
    signed_names =
      tags
      |> Map.get("h", "")
      |> String.split(":", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    # For repeated fields the signer consumes occurrences bottom-up. Walk the
    # message order reversed and pop one matching header per requested name.
    {signed_lines, _remaining} =
      Enum.reduce(signed_names, {[], Enum.reverse(headers)}, fn name, {acc, remaining} ->
        downcased = String.downcase(name)

        case Enum.split_while(remaining, fn {n, _raw} -> String.downcase(String.trim(n)) != downcased end) do
          {_skip, []} ->
            {acc, remaining}

          {skip, [{_n, raw} | rest]} ->
            {[canonicalize_header_string(raw, header_canon) <> "\r\n" | acc], skip ++ rest}
        end
      end)

    # The DKIM-Signature header itself is signed last, with an empty b= value
    # and no trailing CRLF.
    sig_without_b = strip_b_value(sig_header)

    IO.iodata_to_binary([
      Enum.reverse(signed_lines),
      canonicalize_header_string(sig_without_b, header_canon)
    ])
  end

  defp strip_b_value(sig_header) do
    # Blank only the b= tag value, keeping the tag and the rest of the header.
    # Every `;` in a DKIM-Signature is a real tag separator (base64 has no `;`),
    # so requiring a preceding `;` avoids matching a stray "b=" inside bh=.
    Regex.replace(~r/(;\s*)b(\s*)=[^;]*/s, sig_header, "\\1b\\2=", global: false)
  end

  # -- Canonicalization (RFC 6376 3.4) --

  defp canonicalize_header_string(header, canon) do
    case String.split(header, ":", parts: 2) do
      [name, value] -> canonicalize_header(name, value, canon)
      [only] -> canonicalize_header(only, "", canon)
    end
  end

  defp canonicalize_header(name, value, :simple), do: "#{name}:#{value}"

  defp canonicalize_header(name, value, :relaxed) do
    unfolded =
      value
      |> String.replace("\r\n", "")
      |> String.replace(~r/[ \t]+/, " ")
      |> String.trim()

    "#{String.downcase(String.trim(name))}:#{unfolded}"
  end

  defp canonicalize_body(body, :simple) do
    trimmed = String.replace(body, ~r/(\r\n)+\z/, "")
    if trimmed == "", do: "\r\n", else: trimmed <> "\r\n"
  end

  defp canonicalize_body(body, :relaxed) do
    canonical =
      body
      |> String.split("\r\n")
      |> Enum.map_join("\r\n", fn line ->
        line
        |> String.replace(~r/[ \t]+/, " ")
        |> String.replace(~r/[ \t]+\z/, "")
      end)
      |> String.replace(~r/(\r\n)+\z/, "")

    if canonical == "", do: "", else: canonical <> "\r\n"
  end

  # -- Parsing --

  defp split_message(message) do
    case :binary.split(message, "\r\n\r\n") do
      [header_block, body] -> {header_block, body}
      [header_block] -> {header_block, ""}
    end
  end

  defp parse_headers(header_block) do
    header_block
    |> String.split("\r\n")
    |> Enum.reduce([], fn line, acc ->
      cond do
        acc == [] ->
          [line]

        String.match?(line, ~r/^[ \t]/) ->
          [prev | rest] = acc
          [prev <> "\r\n" <> line | rest]

        true ->
          [line | acc]
      end
    end)
    |> Enum.reverse()
    |> Enum.flat_map(fn raw ->
      case String.split(raw, ":", parts: 2) do
        [name, _value] -> [{name, raw}]
        _ -> []
      end
    end)
  end

  defp tag_value(raw_header) do
    case String.split(raw_header, ":", parts: 2) do
      [_name, value] -> value
      [value] -> value
    end
  end

  defp parse_tag_list(value) do
    value
    |> String.split(";", trim: true)
    |> Enum.flat_map(fn pair ->
      case String.split(pair, "=", parts: 2) do
        [k, v] -> [{String.trim(k), String.trim(v)}]
        _ -> []
      end
    end)
    |> Map.new()
  end

  defp algorithm("rsa-sha256"), do: {:ok, {:rsa, :sha256}}
  defp algorithm("rsa-sha1"), do: {:ok, {:rsa, :sha}}
  defp algorithm("ed25519-sha256"), do: {:ok, {:ed25519, :sha256}}
  defp algorithm(_other), do: :error

  defp canonicalization(nil), do: {:simple, :simple}

  defp canonicalization(value) do
    case String.split(value, "/", parts: 2) do
      [header] -> {canon(header), :simple}
      [header, body] -> {canon(header), canon(body)}
    end
  end

  defp canon("relaxed"), do: :relaxed
  defp canon(_), do: :simple

  defp decode_b64(nil), do: :error

  defp decode_b64(value) do
    value
    |> String.replace(~r/\s/, "")
    |> Base.decode64()
    |> case do
      {:ok, decoded} -> {:ok, decoded}
      :error -> :error
    end
  end

  defp normalize_crlf(message) do
    message
    |> String.replace("\r\n", "\n")
    |> String.replace("\n", "\r\n")
  end
end
