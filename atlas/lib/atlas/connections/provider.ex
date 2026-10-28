defmodule Atlas.Connections.Provider do
  @moduledoc false

  alias Atlas.Connections.Config

  @providers %{
    "github" => %{
      name: "GitHub",
      authorize_url: "https://github.com/login/oauth/authorize",
      token_url: "https://github.com/login/oauth/access_token",
      profile_url: "https://api.github.com/user",
      # GitHub App permissions come from its registration, not OAuth scopes.
      scopes: ~w(offline_access)
    },
    "slack" => %{
      name: "Slack",
      authorize_url: "https://slack.com/oauth/v2/authorize",
      token_url: "https://slack.com/api/oauth.v2.access",
      profile_url: "https://slack.com/api/auth.test",
      scopes: ~w(search:read chat:write)
    },
    "google" => %{
      name: "Google",
      authorize_url: "https://accounts.google.com/o/oauth2/v2/auth",
      token_url: "https://oauth2.googleapis.com/token",
      profile_url: "https://www.googleapis.com/oauth2/v3/userinfo",
      scopes: [
        "openid",
        "email",
        "profile",
        "https://www.googleapis.com/auth/drive.file",
        "https://www.googleapis.com/auth/calendar.readonly"
      ]
    }
  }

  def providers, do: ~w(github slack google)

  def config(provider) do
    case Map.fetch(@providers, provider) do
      {:ok, config} ->
        {:ok, Map.merge(config, Config.credentials(provider))}

      :error ->
        {:error, :unsupported_provider}
    end
  end

  def configured?(provider) do
    case config(provider) do
      {:ok, %{client_id: id, client_secret: secret}} -> present?(id) and present?(secret)
      _ -> false
    end
  end

  def authorization_url(provider, redirect_uri, state, verifier) do
    with {:ok, config} <- configured(provider) do
      params = %{
        "client_id" => config.client_id,
        "redirect_uri" => redirect_uri,
        "response_type" => "code",
        "state" => state
      }

      params =
        case provider do
          "slack" ->
            Map.put(params, "user_scope", Enum.join(config.scopes, ","))

          _ ->
            challenge = :sha256 |> :crypto.hash(verifier) |> Base.url_encode64(padding: false)

            params
            |> Map.put("scope", Enum.join(config.scopes, " "))
            |> Map.put("code_challenge", challenge)
            |> Map.put("code_challenge_method", "S256")
        end

      params =
        if provider == "google",
          do: Map.merge(params, %{"access_type" => "offline", "prompt" => "consent"}),
          else: params

      {:ok, config.authorize_url <> "?" <> URI.encode_query(params)}
    end
  end

  def exchange(provider, code, redirect_uri, verifier) do
    params = %{"grant_type" => "authorization_code", "code" => code, "redirect_uri" => redirect_uri}
    params = if provider == "slack", do: params, else: Map.put(params, "code_verifier", verifier)

    with {:ok, attrs} <- token_request(provider, params),
         {:ok, identity} <- identity(provider, attrs.access_token) do
      {:ok, Map.merge(attrs, identity)}
    end
  end

  def refresh(provider, refresh_token) do
    token_request(provider, %{"grant_type" => "refresh_token", "refresh_token" => refresh_token})
  end

  defp configured(provider) do
    if configured?(provider), do: config(provider), else: {:error, :not_configured}
  end

  defp token_request(provider, params) do
    with {:ok, config} <- configured(provider),
         {:ok, body} <-
           request(:post, config.token_url,
             form: Map.merge(params, %{"client_id" => config.client_id, "client_secret" => config.client_secret})
           ) do
      # A Slack install may also return a bot token. Only retain the user's token.
      token = if provider == "slack", do: body["authed_user"] || body, else: body

      if provider != "slack" || token["token_type"] == "user",
        do: token_attrs(token),
        else: {:error, :missing_user_token}
    end
  end

  defp token_attrs(%{"access_token" => token} = body) when is_binary(token) and token != "" do
    {:ok,
     %{
       access_token: token,
       refresh_token: body["refresh_token"],
       scopes: String.split(body["scope"] || "", [" ", ","], trim: true),
       expires_at: expires_at(body["expires_in"]),
       needs_authorization: false
     }}
  end

  defp token_attrs(_body), do: {:error, :invalid_token_response}

  defp identity(provider, token) do
    {:ok, config} = config(provider)

    with {:ok, body} <- request(:get, config.profile_url, auth: {:bearer, token}) do
      profile(provider, body)
    end
  end

  defp profile("github", %{"id" => id, "login" => login}) do
    {:ok, %{provider_user_id: to_string(id), account_name: login, workspace_id: nil}}
  end

  defp profile("slack", %{"user_id" => id, "user" => name, "team_id" => team_id} = body) do
    {:ok, %{provider_user_id: id, account_name: "#{name} · #{body["team"] || team_id}", workspace_id: team_id}}
  end

  defp profile("google", %{"sub" => id, "email" => email}) do
    {:ok, %{provider_user_id: id, account_name: email, workspace_id: nil}}
  end

  defp profile(_provider, _body), do: {:error, :invalid_profile_response}

  defp request(method, url, opts) do
    opts = Keyword.merge([headers: [{"accept", "application/json"}], retry: false, redirect: false], opts)

    case Req.request([method: method, url: url] ++ opts) do
      {:ok, %Req.Response{body: %{"error" => "invalid_grant"}}} ->
        {:error, :needs_authorization}

      {:ok, %Req.Response{body: %{"error" => error}}}
      when error in ["invalid_refresh_token", "token_revoked", "bad_refresh_token"] ->
        {:error, :needs_authorization}

      {:ok, %Req.Response{body: %{"ok" => false}}} ->
        {:error, :provider_rejected}

      {:ok, %Req.Response{body: %{"error" => _}}} ->
        {:error, :provider_rejected}

      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 and is_map(body) ->
        {:ok, body}

      _ ->
        {:error, :provider_unavailable}
    end
  end

  defp expires_at(nil), do: nil

  defp expires_at(seconds) when is_integer(seconds) and seconds > 0 do
    DateTime.utc_now() |> DateTime.add(seconds, :second) |> DateTime.truncate(:second)
  end

  defp expires_at(seconds) when is_binary(seconds) do
    case Integer.parse(seconds) do
      {seconds, ""} -> expires_at(seconds)
      _ -> nil
    end
  end

  defp expires_at(_seconds), do: nil

  defp present?(value), do: is_binary(value) and value != ""
end
