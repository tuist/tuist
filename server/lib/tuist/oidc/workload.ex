defmodule Tuist.OIDC.Workload do
  @moduledoc false

  alias Tuist.OAuth2.SSRFGuard
  alias Tuist.OIDC.JWKSCache
  alias Tuist.OIDC.JWKSClient
  alias Tuist.Projects
  alias Tuist.Projects.OIDCTrustPolicy

  @algorithms ~w(RS256 RS384 RS512 PS256 PS384 PS512 ES256 ES384 EdDSA)
  @maximum_response_bytes 65_536

  def claims(_token, _issuer, account_handle) when account_handle in [nil, ""], do: {:error, :oidc_account_required}

  def claims(token, issuer, account_handle) do
    with {:ok, header, hints} <- peek(token),
         policies when length(policies) in 1..20 <- Projects.oidc_trust_candidates(issuer, account_handle, hints),
         groups when map_size(groups) <= 2 <- Enum.group_by(policies, & &1.jwks_url) do
      grants =
        Enum.flat_map(groups, fn {url, policies} ->
          with %{"keys" => keys} <- fetch_jwks(url),
               {:ok, verified} <- verify(token, header, keys) do
            policies
            |> Enum.filter(&OIDCTrustPolicy.matches?(&1, verified))
            |> Enum.map(&%{policy_id: &1.id, jwks_url: url, claims: verified})
          else
            _ -> []
          end
        end)

      if grants == [],
        do: {:error, :invalid_signature},
        else: {:ok, %{provider: :oidc, account_handle: account_handle, grants: grants}}
    else
      _ -> {:error, :invalid_signature}
    end
  rescue
    _ -> {:error, :invalid_signature}
  end

  defp peek(token) do
    with [header, payload, _signature] <- String.split(token, "."),
         {:ok, header} <- Base.url_decode64(header, padding: false),
         {:ok, %{"alg" => algorithm} = header} <- JSON.decode(header),
         true <- algorithm in @algorithms and not Map.has_key?(header, "crit"),
         {:ok, payload} <- Base.url_decode64(payload, padding: false),
         {:ok, payload} when is_map(payload) <- JSON.decode(payload) do
      {:ok, header, payload}
    else
      _ -> :error
    end
  end

  defp fetch_jwks(url) do
    JWKSCache.get_or_update(url, fn ->
      # The stream task bounds total duration, not just idle time between chunks.
      [url]
      |> Task.async_stream(&request_jwks/1, timeout: 8_000, on_timeout: :kill_task)
      |> Enum.at(0)
      |> case do
        {:ok, jwks} -> jwks
        _ -> nil
      end
    end)
  end

  defp request_jwks(url) do
    with true <- OIDCTrustPolicy.https_url?(url),
         {:ok, pinned_url, hostname} <- SSRFGuard.pin(url),
         {:ok, %{status: 200, body: body}} when is_binary(body) <-
           JWKSClient.get(pinned_url,
             connect_options: Keyword.put(SSRFGuard.connect_options(hostname), :timeout, 5_000),
             receive_timeout: 5_000,
             redirect: false,
             retry: false,
             decode_body: false,
             headers: [{"accept", "application/json"}],
             into: &bounded_response/2
           ),
         true <- byte_size(body) <= @maximum_response_bytes,
         {:ok, %{"keys" => keys}} when is_list(keys) and length(keys) in 1..20 <- JSON.decode(body),
         keys when keys != [] <- Enum.filter(keys, &eligible_key?/1) do
      %{"keys" => Enum.map(keys, &normalize_key/1)}
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp bounded_response({:data, chunk}, {request, response}) do
    body = response.body || ""

    if byte_size(body) + byte_size(chunk) <= @maximum_response_bytes do
      {:cont, {request, %{response | body: body <> chunk}}}
    else
      {:halt, {request, %{response | body: :response_too_large}}}
    end
  end

  defp eligible_key?(%{"kty" => "RSA", "n" => n, "e" => e} = key) do
    with true <- signing_key?(key),
         {:ok, modulus} <- Base.url_decode64(n, padding: false),
         true <- byte_size(modulus) in 256..512,
         true <- byte_size(modulus) > 256 or :binary.first(modulus) >= 128,
         {:ok, exponent} <- Base.url_decode64(e, padding: false),
         true <- byte_size(exponent) in 1..4 do
      exponent = :binary.decode_unsigned(exponent)
      exponent in 3..65_537 and rem(exponent, 2) == 1
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp eligible_key?(%{"kty" => "EC", "crv" => curve, "x" => x, "y" => y} = key) do
    size = if curve == "P-256", do: 32, else: 48
    curve in ["P-256", "P-384"] and signing_key?(key) and coordinate?(x, size) and coordinate?(y, size)
  end

  defp eligible_key?(%{"kty" => "OKP", "crv" => "Ed25519", "x" => x} = key) do
    signing_key?(key) and coordinate?(x, 32)
  end

  defp eligible_key?(_), do: false

  defp coordinate?(value, size) when is_binary(value) do
    case Base.url_decode64(value, padding: false) do
      {:ok, coordinate} -> byte_size(coordinate) == size
      _ -> false
    end
  end

  defp coordinate?(_, _), do: false

  defp signing_key?(key) do
    key_id_valid?(key) and Map.get(key, "use", "sig") == "sig" and Map.get(key, "alg", "RS256") in @algorithms and
      (not Map.has_key?(key, "key_ops") or (is_list(key["key_ops"]) and "verify" in key["key_ops"]))
  end

  defp key_id_valid?(%{"kid" => kid}), do: is_binary(kid) and byte_size(kid) <= 256
  defp key_id_valid?(_), do: true

  defp normalize_key(key) do
    fields =
      case key["kty"] do
        "RSA" -> ~w(n e)
        "EC" -> ~w(crv x y)
        "OKP" -> ~w(crv x)
      end

    Map.take(key, ~w(kty kid alg) ++ fields)
  end

  defp verify(token, header, keys) do
    keys = Enum.filter(keys, &key_matches_header?(&1, header))

    keys =
      case header["kid"] do
        nil -> if length(keys) == 1, do: keys, else: []
        kid when is_binary(kid) -> Enum.filter(keys, &(&1["kid"] == kid))
        _ -> []
      end

    Enum.find_value(keys, {:error, :invalid_signature}, fn key -> verify_key(token, header["alg"], key) end)
  end

  defp key_matches_header?(key, %{"alg" => algorithm}) do
    (not Map.has_key?(key, "alg") or key["alg"] == algorithm) and
      case key do
        %{"kty" => "RSA"} -> algorithm in ~w(RS256 RS384 RS512 PS256 PS384 PS512)
        %{"kty" => "EC", "crv" => "P-256"} -> algorithm == "ES256"
        %{"kty" => "EC", "crv" => "P-384"} -> algorithm == "ES384"
        %{"kty" => "OKP"} -> algorithm == "EdDSA"
      end
  end

  defp verify_key(token, algorithm, key) do
    now = DateTime.to_unix(DateTime.utc_now())

    with {true, %JOSE.JWT{fields: claims}, _} <- JOSE.JWT.verify_strict(JOSE.JWK.from_map(key), [algorithm], token),
         exp when is_integer(exp) and exp > now <- claims["exp"],
         true <- not_before_valid?(claims, now) do
      {:ok, claims}
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp not_before_valid?(%{"nbf" => nbf}, now) when is_integer(nbf), do: nbf <= now + 60
  defp not_before_valid?(%{"nbf" => _}, _), do: false
  defp not_before_valid?(_, _), do: true
end
