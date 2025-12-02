defmodule Runner.Runner.GitHub.Registration do
  @moduledoc """
  Handles runner registration with GitHub Actions.

  This module implements the "just in time" (JIT) runner configuration protocol
  used by GitHub Actions. When a runner registers, it receives:
  - An RSA private key for JWT signing
  - Broker API URLs for session management and job polling
  - Runner credentials for authentication
  """

  require Logger

  alias Runner.Runner.GitHub.Auth

  @github_api_base "https://api.github.com"
  @runner_version "2.320.0"

  @type registration_params :: %{
          github_org: String.t(),
          github_repo: String.t() | nil,
          labels: [String.t()],
          runner_name: String.t()
        }

  @type registration_result :: %{
          runner_id: integer(),
          server_url: String.t(),
          server_url_v2: String.t(),
          auth_url: String.t(),
          rsa_private_key: String.t(),
          credentials: Auth.credentials()
        }

  @doc """
  Registers a new runner with GitHub using a registration token.

  This performs the JIT configuration request that the official runner
  does when running `config.sh`. Returns all the credentials needed
  to create sessions and poll for jobs.
  """
  @spec register(String.t(), registration_params()) ::
          {:ok, registration_result()} | {:error, term()}
  def register(registration_token, params) do
    url = build_registration_url(params)

    body =
      Jason.encode!(%{
        name: params.runner_name,
        runner_group_id: 1,
        labels: build_labels(params.labels),
        work_folder: "_work",
        version: @runner_version,
        ephemeral: true
      })

    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{registration_token}"},
      {"Accept", "application/vnd.github+json"},
      {"X-GitHub-Api-Version", "2022-11-28"},
      {"User-Agent", "GitHubActionsRunner/#{@runner_version}"}
    ]

    Logger.info("Registering runner '#{params.runner_name}' with GitHub")

    case Req.post(url, headers: headers, body: body, receive_timeout: 30_000) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        Logger.info("Registration response keys: #{inspect(Map.keys(body))}")
        parse_registration_response(body, params)

      {:ok, %Req.Response{status: 201, body: body}} ->
        Logger.info("Registration response keys: #{inspect(Map.keys(body))}")
        parse_registration_response(body, params)

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Registration failed: status=#{status}, body=#{inspect(body)}")
        {:error, {:registration_failed, status, body}}

      {:error, reason} ->
        Logger.error("Registration request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Removes a runner registration from GitHub.

  Should be called during graceful shutdown to clean up the runner.
  """
  @spec unregister(registration_result()) :: :ok | {:error, term()}
  def unregister(registration) do
    # The runner removal is typically done via the credentials
    # For ephemeral runners, this happens automatically after job completion
    Logger.info("Unregistering runner #{registration.runner_id}")
    :ok
  end

  # Private functions

  defp build_registration_url(%{github_repo: nil, github_org: org}) do
    "#{@github_api_base}/orgs/#{org}/actions/runners/generate-jitconfig"
  end

  defp build_registration_url(%{github_org: org, github_repo: repo}) do
    "#{@github_api_base}/repos/#{org}/#{repo}/actions/runners/generate-jitconfig"
  end

  defp build_labels(labels) do
    # GitHub JIT config API expects labels as simple strings
    labels
  end

  defp parse_registration_response(body, params) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse_registration_response(decoded, params)
      {:error, _} = error -> error
    end
  end

  defp parse_registration_response(body, _params) when is_map(body) do
    runner_id = body["runner"]["id"]
    encoded_jit_config = body["encoded_jit_config"]

    # The JIT config is base64-encoded JSON containing all credentials
    case decode_jit_config(encoded_jit_config) do
      {:ok, jit_config} ->
        # The JIT config uses dot-prefixed keys
        # .runner is a base64-encoded JSON with PascalCase keys
        runner_settings = parse_runner_settings(jit_config[".runner"])
        server_url = runner_settings["ServerUrl"] || runner_settings["serverUrl"]
        server_url_v2 = runner_settings["ServerUrlV2"] || runner_settings["serverUrlV2"]
        github_url = runner_settings["GitHubUrl"] || runner_settings["gitHubUrl"]
        pool_id = runner_settings["PoolId"] || runner_settings["poolId"]
        agent_id = runner_settings["AgentId"] || runner_settings["agentId"]

        # Auth URL comes from .credentials (also base64-encoded JSON with Data.AuthorizationUrl)
        credentials_data = parse_credentials_data(jit_config[".credentials"])
        auth_url = credentials_data["AuthorizationUrl"] || credentials_data["authorizationUrl"]
        client_id = credentials_data["ClientId"] || credentials_data["clientId"]
        rsa_private_key = extract_private_key_from_jit(jit_config)

        Logger.debug("Parsed JIT config - server_url: #{server_url}, server_url_v2: #{server_url_v2}")

        credentials = %{
          runner_id: to_string(runner_id),
          rsa_private_key: rsa_private_key,
          auth_url: auth_url,
          client_id: client_id,
          access_token: nil,
          token_expires_at: nil
        }

        {:ok,
         %{
           runner_id: runner_id,
           agent_id: agent_id,
           pool_id: pool_id,
           server_url: server_url,
           server_url_v2: server_url_v2,
           github_url: github_url,
           auth_url: auth_url,
           rsa_private_key: rsa_private_key,
           credentials: credentials,
           # Include the raw encoded JIT config for use with official runner binary
           encoded_jit_config: encoded_jit_config
         }}

      {:error, reason} ->
        {:error, {:jit_config_parse_error, reason}}
    end
  end

  defp parse_credentials_data(nil), do: %{}

  defp parse_credentials_data(encoded) when is_binary(encoded) do
    # Decode base64, then extract Data field
    case Base.decode64(encoded) do
      {:ok, decoded} ->
        case Jason.decode(decoded) do
          {:ok, %{"Data" => data}} when is_map(data) -> data
          {:ok, %{"data" => data}} when is_map(data) -> data
          {:ok, map} -> map
          _ -> %{}
        end

      :error ->
        %{}
    end
  end

  defp parse_runner_settings(nil), do: %{}

  defp parse_runner_settings(settings) when is_binary(settings) do
    # The .runner value is a base64-encoded JSON string
    case Base.decode64(settings) do
      {:ok, decoded} ->
        case Jason.decode(decoded) do
          {:ok, map} -> map
          _ -> %{}
        end

      :error ->
        %{}
    end
  end

  defp parse_runner_settings(settings) when is_list(settings) do
    # Convert list of key-value strings to a map
    # e.g., ["gitHubUrl", "https://github.com", "serverUrlV2", "https://..."]
    settings
    |> Enum.chunk_every(2)
    |> Enum.reduce(%{}, fn
      [key, value], acc -> Map.put(acc, key, value)
      _, acc -> acc
    end)
  end

  defp parse_runner_settings(settings) when is_map(settings), do: settings

  defp decode_jit_config(encoded) when is_binary(encoded) do
    case Base.decode64(encoded) do
      {:ok, decoded} ->
        case Jason.decode(decoded) do
          {:ok, config} -> {:ok, config}
          {:error, reason} -> {:error, {:json_decode_error, reason}}
        end

      :error ->
        {:error, :base64_decode_error}
    end
  end

  defp decode_jit_config(_), do: {:error, :missing_jit_config}

  defp extract_private_key_from_jit(jit_config) do
    # The JIT config uses dot-prefixed keys
    # .credentials_rsaparams contains the RSA private key (base64-encoded JSON with PEM inside)
    cond do
      is_binary(jit_config[".credentials_rsaparams"]) ->
        extract_rsa_from_params(jit_config[".credentials_rsaparams"])

      is_binary(jit_config["credentials_rsaparams"]) ->
        extract_rsa_from_params(jit_config["credentials_rsaparams"])

      true ->
        Logger.warning("Could not find RSA key in JIT config: #{inspect(Map.keys(jit_config))}")
        nil
    end
  end

  defp extract_rsa_from_params(encoded) when is_binary(encoded) do
    case Base.decode64(encoded) do
      {:ok, decoded} ->
        case Jason.decode(decoded) do
          # GitHub's RSA format with d, dp, dq, exponent, inverseQ, modulus, p, q
          {:ok, %{"d" => _, "modulus" => _, "exponent" => _} = rsa_params} ->
            # Convert to JWK format for JOSE
            convert_github_rsa_to_jwk(rsa_params)

          {:ok, %{"Data" => pem}} when is_binary(pem) ->
            pem

          {:ok, %{"data" => pem}} when is_binary(pem) ->
            pem

          {:ok, other} ->
            Logger.warning("Unexpected RSA params format: #{inspect(Map.keys(other))}")
            nil

          _ ->
            # Maybe it's directly a PEM string
            if String.contains?(decoded, "PRIVATE KEY") do
              decoded
            else
              nil
            end
        end

      :error ->
        # Maybe it's not base64, try using it directly
        if String.contains?(encoded, "PRIVATE KEY") do
          encoded
        else
          nil
        end
    end
  end

  defp convert_github_rsa_to_jwk(rsa_params) do
    # GitHub provides RSA params with PascalCase keys and standard base64-encoded values
    # JWK requires base64url encoding without padding
    # Note: GitHub uses "modulus" for n, "exponent" for e, "inverseQ" for qi
    %{
      "kty" => "RSA",
      "n" => base64_to_base64url(rsa_params["modulus"]),
      "e" => base64_to_base64url(rsa_params["exponent"]),
      "d" => base64_to_base64url(rsa_params["d"]),
      "p" => base64_to_base64url(rsa_params["p"]),
      "q" => base64_to_base64url(rsa_params["q"]),
      "dp" => base64_to_base64url(rsa_params["dp"]),
      "dq" => base64_to_base64url(rsa_params["dq"]),
      "qi" => base64_to_base64url(rsa_params["inverseQ"])
    }
  end

  defp base64_to_base64url(nil), do: nil

  defp base64_to_base64url(b64) when is_binary(b64) do
    # Convert standard base64 to base64url (URL-safe, no padding)
    b64
    |> String.replace("+", "-")
    |> String.replace("/", "_")
    |> String.trim_trailing("=")
  end
end
