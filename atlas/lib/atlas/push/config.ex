defmodule Atlas.Push.Config do
  @moduledoc """
  Server-only push provider credentials.

  `parse!/1` runs from `config/runtime.exs`. Each provider is either fully
  configured or absent; partial or malformed values fail the boot rather than
  silently disabling delivery. Absent providers make the platform unavailable,
  which native clients learn from `GET /api/native/profile`.
  """

  @apns_topic "dev.tuist.atlas"
  @apns_vars ~w(ATLAS_APNS_TEAM_ID ATLAS_APNS_KEY_ID ATLAS_APNS_PRIVATE_KEY)
  @fcm_var "ATLAS_FCM_SERVICE_ACCOUNT_JSON"
  @apple_identifier ~r/\A[A-Z0-9]{10}\z/
  @firebase_project ~r/\A[a-z][a-z0-9-]{4,28}[a-z0-9]\z/

  def apns_topic, do: @apns_topic

  def apns do
    case Keyword.get(config(), :apns) do
      %{} = apns -> {:ok, apns}
      _ -> {:error, :not_configured}
    end
  end

  def apns_for(environment) when environment in ["sandbox", "production"] do
    with {:ok, apns} <- __MODULE__.apns(),
         true <- Map.get(apns, :environment, "production") in ["both", environment] do
      {:ok, apns}
    else
      _ -> {:error, :not_configured}
    end
  end

  def fcm do
    case Keyword.get(config(), :fcm) do
      %{} = fcm -> {:ok, fcm}
      _ -> {:error, :not_configured}
    end
  end

  def capabilities do
    %{"ios" => match?({:ok, _}, apns()), "android" => match?({:ok, _}, fcm())}
  end

  def available?(platform), do: Map.get(capabilities(), platform, false)

  def available?("ios", environment), do: match?({:ok, _}, apns_for(environment))
  def available?("android", "production"), do: available?("android")
  def available?(_platform, _environment), do: false

  @doc false
  def req_options, do: Keyword.get(config(), :req_options, [])

  def parse!(env) when is_map(env) do
    [apns: parse_apns!(env), fcm: parse_fcm!(env)]
  end

  defp parse_apns!(env) do
    values = Enum.map(@apns_vars, &present(env, &1))

    case values do
      [nil, nil, nil] ->
        nil

      [team_id, key_id, private_key] when is_binary(team_id) and is_binary(key_id) and is_binary(private_key) ->
        if !Regex.match?(@apple_identifier, team_id), do: raise("ATLAS_APNS_TEAM_ID must be a 10-character team ID")
        if !Regex.match?(@apple_identifier, key_id), do: raise("ATLAS_APNS_KEY_ID must be a 10-character key ID")
        ensure_key!(private_key, "EC", "ATLAS_APNS_PRIVATE_KEY must be a PEM-encoded P-256 APNs signing key")
        %{team_id: team_id, key_id: key_id, private_key: private_key, environment: parse_apns_environment!(env)}

      _ ->
        raise "Set ATLAS_APNS_TEAM_ID, ATLAS_APNS_KEY_ID and ATLAS_APNS_PRIVATE_KEY together, or none of them"
    end
  end

  defp parse_apns_environment!(env) do
    environment = present(env, "ATLAS_APNS_ENVIRONMENT") || "production"

    if environment not in ["production", "sandbox", "both"],
      do: raise("ATLAS_APNS_ENVIRONMENT must be production, sandbox or both")

    environment
  end

  defp parse_fcm!(env) do
    case present(env, @fcm_var) do
      nil ->
        nil

      json ->
        account =
          case JSON.decode(json) do
            {:ok, %{} = account} -> account
            _ -> raise "#{@fcm_var} must be a Firebase service account JSON object"
          end

        with "service_account" <- account["type"],
             project_id when is_binary(project_id) <- account["project_id"],
             true <- Regex.match?(@firebase_project, project_id),
             email when is_binary(email) and email != "" <- account["client_email"],
             key when is_binary(key) <- account["private_key"] do
          ensure_key!(key, "RSA", "#{@fcm_var} must contain an RSA private_key")
          %{project_id: project_id, client_email: email, private_key: key}
        else
          _ -> raise "#{@fcm_var} must contain type, project_id, client_email and private_key"
        end
    end
  end

  # Credential parse failures must never echo key material.
  defp ensure_key!(pem, expected_type, message) do
    with :ok <- valid_armor(pem),
         [{type, _der, :not_encrypted}] when type in [:PrivateKeyInfo, :ECPrivateKey, :RSAPrivateKey] <-
           :public_key.pem_decode(pem),
         %JOSE.JWK{} = jwk <- JOSE.JWK.from_pem(pem),
         {_fields, %{"kty" => ^expected_type} = key} <- JOSE.JWK.to_map(jwk),
         true <- expected_type != "EC" or key["crv"] == "P-256" do
      :ok
    else
      _ -> raise message
    end
  end

  # `:public_key.pem_decode/1` raises on corrupt base64, so check the body first.
  @armor ~r/\A\s*-----BEGIN ([A-Z ]+)-----\s*([A-Za-z0-9+\/=\s]+?)\s*-----END \1-----\s*\z/
  defp valid_armor(pem) do
    with [_, _label, body] <- Regex.run(@armor, pem),
         {:ok, _der} <- Base.decode64(body, ignore: :whitespace) do
      :ok
    else
      _ -> :error
    end
  end

  defp present(env, name) do
    env
    |> Map.get(name, "")
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp config, do: Application.get_env(:atlas, Atlas.Push, [])
end
