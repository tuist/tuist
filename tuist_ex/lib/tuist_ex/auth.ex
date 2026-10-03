defmodule TuistEx.Auth do
  @moduledoc false

  alias TuistEx.{HTTP, Lock}

  @default_url "https://tuist.dev"

  def login(options \\ []) do
    environment = Keyword.get(options, :environment, &System.get_env/1)
    server_url = server_url(options, environment)
    email = Keyword.get(options, :email)
    password = Keyword.get(options, :password)

    credentials =
      cond do
        email || password -> password_login(server_url, email, password, options)
        continuous_integration?(environment) -> provider_login(server_url, environment, options)
        true -> browser_login(server_url, options)
      end

    case Lock.with_lock(lock_path(server_url, environment), fn ->
           save(credentials_path(server_url, environment), credentials)
         end) do
      :ok -> :ok
      {:error, reason} -> Mix.raise(reason)
    end
  end

  def token(options \\ []) do
    environment = Keyword.get(options, :environment, &System.get_env/1)

    case environment.("TUIST_TOKEN") do
      token when is_binary(token) and token != "" -> {:ok, token}
      _ -> stored_token(server_url(options, environment), environment)
    end
  end

  defp server_url(options, environment) do
    project_url = Keyword.get(Mix.Project.config()[:tuist] || [], :url)
    url = environment.("TUIST_URL") || Keyword.get(options, :url) || project_url || @default_url
    uri = URI.parse(url)

    if uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" and
         is_nil(uri.userinfo) and is_nil(uri.query) and is_nil(uri.fragment) do
      String.trim_trailing(url, "/")
    else
      Mix.raise("Invalid server URL: #{url}")
    end
  end

  defp password_login(server_url, email, password, options) do
    prompt = Keyword.get(options, :prompt, &default_prompt/1)
    email = email || prompt.(:email)
    password = password || prompt.(:password)

    case HTTP.request(:post, server_url <> "/api/auth", %{email: email, password: password}) do
      {:ok, 200, %{"access_token" => access, "refresh_token" => refresh}} ->
        %{"accessToken" => access, "refreshToken" => refresh}

      response ->
        request_error!("Email and password authentication", response)
    end
  end

  defp browser_login(server_url, options) do
    code =
      Keyword.get(options, :device_code, fn ->
        Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
      end).()

    browser_url = server_url <> "/auth/device_codes/#{code}?type=cli"
    Mix.shell().info("Opening #{browser_url} to start authentication")

    case Keyword.get(options, :open_browser, &open_browser/1).(browser_url) do
      :ok -> :ok
      {:error, reason} -> Mix.shell().info("Open the address above in a browser: #{reason}")
    end

    Mix.shell().info("Press Control-C to cancel.")
    sleep = Keyword.get(options, :sleep, &Process.sleep/1)
    poll_device_code(server_url, code, sleep, 300)
  end

  defp poll_device_code(_server_url, _code, _sleep, 0),
    do: Mix.raise("Tuist authentication timed out")

  defp poll_device_code(server_url, code, sleep, attempts) do
    case HTTP.request(:get, server_url <> "/api/auth/device_code/#{code}") do
      {:ok, 200, %{"access_token" => access, "refresh_token" => refresh}} ->
        %{"accessToken" => access, "refreshToken" => refresh}

      {:ok, 202, _} ->
        sleep.(1_000)
        poll_device_code(server_url, code, sleep, attempts - 1)

      {:ok, status, _} when status >= 500 ->
        sleep.(1_000)
        poll_device_code(server_url, code, sleep, attempts - 1)

      {:error, _} ->
        sleep.(1_000)
        poll_device_code(server_url, code, sleep, attempts - 1)

      response ->
        request_error!("Browser authentication", response)
    end
  end

  defp provider_login(server_url, environment, options) do
    Mix.shell().info("Detected continuous integration, authenticating with OpenID Connect.")

    identity_token =
      Keyword.get(options, :identity_token, fn -> fetch_identity_token(environment) end).()

    case HTTP.request(:post, server_url <> "/api/auth/oidc/token", %{token: identity_token}) do
      {:ok, 200, %{"access_token" => access}} -> %{"accessToken" => access}
      response -> request_error!("OpenID Connect authentication", response)
    end
  end

  defp fetch_identity_token(environment) do
    cond do
      truthy?(environment.("GITHUB_ACTIONS")) ->
        request_url =
          environment.("ACTIONS_ID_TOKEN_REQUEST_URL") ||
            Mix.raise("GitHub Actions requires id-token: write permission")

        request_token =
          environment.("ACTIONS_ID_TOKEN_REQUEST_TOKEN") ||
            Mix.raise("GitHub Actions requires id-token: write permission")

        separator = if String.contains?(request_url, "?"), do: "&", else: "?"

        case HTTP.request(:get, request_url <> separator <> "audience=tuist", nil, [
               {"authorization", "Bearer " <> request_token}
             ]) do
          {:ok, 200, %{"value" => value}} -> value
          response -> request_error!("GitHub Actions identity token request", response)
        end

      truthy?(environment.("CIRCLECI")) ->
        environment.("CIRCLE_OIDC_TOKEN_V2") || environment.("CIRCLE_OIDC_TOKEN") ||
          Mix.raise("CircleCI identity token is missing")

      truthy?(environment.("BITRISE_IO")) ->
        environment.("BITRISE_OIDC_ID_TOKEN") || environment.("BITRISE_IDENTITY_TOKEN") ||
          Mix.raise("Bitrise identity token is missing")

      true ->
        Mix.raise("OpenID Connect authentication supports GitHub Actions, CircleCI, and Bitrise")
    end
  end

  defp continuous_integration?(environment) do
    Enum.any?(["CI", "GITHUB_ACTIONS", "CIRCLECI", "BITRISE_IO"], &truthy?(environment.(&1)))
  end

  defp truthy?(value), do: value not in [nil, "", "0", "false", "FALSE"]

  defp default_prompt(:email) do
    case IO.gets("Email: ") do
      email when is_binary(email) -> String.trim(email)
      _ -> Mix.raise("Could not read email. Pass --email or use an interactive terminal")
    end
  end

  defp default_prompt(:password) do
    IO.write("Password: ")

    case :io.get_password() do
      password when is_list(password) -> to_string(password) |> String.trim_trailing("\n")
      _ -> Mix.raise("Could not read password. Pass --password or use an interactive terminal")
    end
  end

  defp open_browser(url) do
    command =
      case :os.type() do
        {:unix, :darwin} -> "open"
        {:unix, _} -> "xdg-open"
        _ -> nil
      end

    if command && System.find_executable(command) do
      case System.cmd(command, [url], stderr_to_stdout: true) do
        {_, 0} -> :ok
        {output, _} -> {:error, String.trim(output)}
      end
    else
      {:error, "No browser opener is available on this system"}
    end
  end

  defp stored_token(server_url, environment) do
    path = credentials_path(server_url, environment)

    with {:ok, credentials} <- read(path),
         access when is_binary(access) <- credentials["accessToken"] do
      if expired?(access) do
        Lock.with_lock(lock_path(server_url, environment), fn ->
          with {:ok, current} <- read(path),
               token when is_binary(token) <- current["accessToken"] do
            if expired?(token), do: refresh(server_url, path, current), else: {:ok, token}
          else
            _ -> {:error, "Run `mix tuist.login` or set TUIST_TOKEN"}
          end
        end)
      else
        {:ok, access}
      end
    else
      _ -> {:error, "Run `mix tuist.login` or set TUIST_TOKEN"}
    end
  end

  defp refresh(server_url, path, %{"refreshToken" => refresh}) when is_binary(refresh) do
    case HTTP.request(:post, server_url <> "/api/auth/refresh_token", %{refresh_token: refresh}) do
      {:ok, 200, %{"access_token" => access, "refresh_token" => new_refresh}} ->
        save(path, %{"accessToken" => access, "refreshToken" => new_refresh})
        {:ok, access}

      {:ok, 401, _} ->
        {:error, "Session expired. Run `mix tuist.login`"}

      {:ok, status, body} ->
        {:error, "Token refresh failed (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Token refresh failed: #{inspect(reason)}"}
    end
  end

  defp refresh(_, _, _), do: {:error, "Session expired. Run `mix tuist.login`"}

  defp expired?(token) do
    with [_, payload, _] <- String.split(token, "."),
         {:ok, decoded} <- Base.url_decode64(payload, padding: false),
         {:ok, %{"exp" => expiration}} <- Jason.decode(decoded) do
      expiration <= System.system_time(:second) + 30
    else
      _ -> true
    end
  end

  defp read(path) do
    with {:ok, content} <- File.read(path), do: Jason.decode(content)
  end

  defp save(path, credentials) do
    directory = Path.dirname(path)
    File.mkdir_p!(directory)
    File.chmod!(directory, 0o700)
    temporary = path <> ".#{System.unique_integer([:positive])}.tmp"
    {:ok, file} = File.open(temporary, [:write, :exclusive])

    try do
      try do
        File.chmod!(temporary, 0o600)
        :ok = IO.binwrite(file, Jason.encode!(credentials))
      after
        File.close(file)
      end

      File.rename!(temporary, path)
      :ok
    after
      File.rm(temporary)
    end
  end

  defp credentials_path(server_url, environment) do
    config_home = configured_home(environment, "XDG_CONFIG_HOME", ".config")

    Path.join([config_home, "tuist", "credentials", "#{URI.parse(server_url).host}.json"])
  end

  defp lock_path(server_url, environment) do
    state_home = configured_home(environment, "XDG_STATE_HOME", ".local/state")
    sanitized = String.replace("token_" <> server_url, ~r{[/ : ]}, "_")
    Path.join([state_home, "tuist", "auth-locks", "#{sanitized}.lock"])
  end

  defp configured_home(environment, name, fallback) do
    candidate = environment.("TUIST_" <> name) || environment.(name)

    if is_binary(candidate) and candidate != "" and Path.type(candidate) == :absolute do
      candidate
    else
      Path.join(System.user_home!(), fallback)
    end
  end

  defp request_error!(label, {:ok, status, body}) do
    message =
      if is_map(body),
        do: Map.get(body, "message", "Unexpected response"),
        else: "Unexpected response"

    Mix.raise("#{label} failed (#{status}): #{message}")
  end

  defp request_error!(label, {:error, reason}),
    do: Mix.raise("#{label} failed: #{inspect(reason)}")
end
