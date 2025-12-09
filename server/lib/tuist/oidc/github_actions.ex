defmodule Tuist.OIDC.GitHubActions do
  @moduledoc """
  GitHub Actions OIDC token validation.

  This module validates JWT tokens issued by GitHub Actions' OIDC provider.
  The tokens are verified against GitHub's public JWKS and validated for
  issuer, expiration, and required claims.

  ## Token Exchange Flow

  1. GitHub Actions workflow requests an OIDC token from GitHub
  2. The token is sent to Tuist's `/api/oidc/token` endpoint
  3. This module verifies the token signature using GitHub's JWKS
  4. Claims are extracted and normalized for authorization

  ## References

  - https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect
  - https://token.actions.githubusercontent.com/.well-known/openid-configuration
  """

  alias Tuist.KeyValueStore

  @issuer "https://token.actions.githubusercontent.com"
  @jwks_uri "https://token.actions.githubusercontent.com/.well-known/jwks"
  @jwks_cache_ttl :timer.minutes(15)

  @type claims :: %{
          repository: String.t(),
          repository_owner: String.t(),
          ref: String.t() | nil,
          workflow: String.t() | nil,
          actor: String.t() | nil,
          run_id: String.t() | nil
        }

  @type error ::
          :invalid_token
          | :invalid_signature
          | :invalid_issuer
          | :token_expired
          | :missing_repository_claim
          | :jwks_fetch_failed

  @doc """
  Verifies a GitHub Actions OIDC token and extracts normalized claims.

  Returns `{:ok, claims}` if the token is valid, where claims includes:
  - `repository`: The repository in "owner/repo" format
  - `repository_owner`: The repository owner
  - `ref`: The git ref (e.g., "refs/heads/main")
  - `workflow`: The workflow name
  - `actor`: The user who triggered the workflow
  - `run_id`: The workflow run ID

  Returns `{:error, reason}` if validation fails.
  """
  @spec verify(String.t()) :: {:ok, claims()} | {:error, error()}
  def verify(token) when is_binary(token) do
    with {:ok, header} <- peek_header(token),
         {:ok, unverified_claims} <- peek_claims(token),
         :ok <- validate_issuer(unverified_claims),
         {:ok, jwks} <- fetch_jwks(),
         {:ok, verified_claims} <- verify_signature(token, jwks, header["kid"]),
         :ok <- validate_expiration(verified_claims),
         {:ok, normalized} <- normalize_claims(verified_claims) do
      {:ok, normalized}
    end
  end

  def verify(_), do: {:error, :invalid_token}

  @doc """
  Returns the expected issuer URL for GitHub Actions OIDC tokens.
  """
  def issuer, do: @issuer

  defp peek_header(token) do
    case String.split(token, ".") do
      [header_b64 | _] ->
        case Base.url_decode64(header_b64, padding: false) do
          {:ok, header_json} ->
            case Jason.decode(header_json) do
              {:ok, header} -> {:ok, header}
              _ -> {:error, :invalid_token}
            end

          _ ->
            {:error, :invalid_token}
        end

      _ ->
        {:error, :invalid_token}
    end
  end

  defp peek_claims(token) do
    try do
      %JOSE.JWT{fields: fields} = JOSE.JWT.peek_payload(token)
      {:ok, fields}
    rescue
      _ -> {:error, :invalid_token}
    end
  end

  defp validate_issuer(%{"iss" => issuer}) when issuer == @issuer, do: :ok
  defp validate_issuer(%{"iss" => _}), do: {:error, :invalid_issuer}
  defp validate_issuer(_), do: {:error, :invalid_issuer}

  defp validate_expiration(%{"exp" => exp}) when is_integer(exp) do
    now = DateTime.utc_now() |> DateTime.to_unix()

    if exp > now do
      :ok
    else
      {:error, :token_expired}
    end
  end

  defp validate_expiration(_), do: {:error, :token_expired}

  defp fetch_jwks do
    cache_key = ["oidc", "github_actions", "jwks"]

    result =
      KeyValueStore.get_or_update(cache_key, [ttl: @jwks_cache_ttl, locking: false], fn ->
        case Req.get(@jwks_uri) do
          {:ok, %{status: 200, body: body}} ->
            {:ok, body}

          _ ->
            {:error, :jwks_fetch_failed}
        end
      end)

    case result do
      {:ok, _} = success -> success
      {:error, _} = error -> error
      jwks when is_map(jwks) -> {:ok, jwks}
    end
  end

  defp verify_signature(token, %{"keys" => keys}, kid) when is_list(keys) do
    key =
      if kid do
        Enum.find(keys, fn k -> k["kid"] == kid end)
      else
        List.first(keys)
      end

    case key do
      nil ->
        {:error, :invalid_signature}

      key_map ->
        jwk = JOSE.JWK.from_map(key_map)

        case JOSE.JWT.verify_strict(jwk, ["RS256"], token) do
          {true, %JOSE.JWT{fields: fields}, _jws} ->
            {:ok, fields}

          _ ->
            {:error, :invalid_signature}
        end
    end
  end

  defp verify_signature(_, _, _), do: {:error, :invalid_signature}

  defp normalize_claims(%{"repository" => repository} = claims) when is_binary(repository) do
    normalized = %{
      repository: repository,
      repository_owner: claims["repository_owner"],
      ref: claims["ref"],
      workflow: claims["workflow"],
      actor: claims["actor"],
      run_id: to_string(claims["run_id"] || "")
    }

    {:ok, normalized}
  end

  defp normalize_claims(_), do: {:error, :missing_repository_claim}
end
