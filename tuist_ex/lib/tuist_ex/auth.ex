defmodule TuistEx.Auth do
  @moduledoc false

  alias TuistEx.Analytics.Config
  alias TuistEx.{HTTP, Lock}

  @default_url "https://tuist.dev"
  @github_identity_token_attempts 5

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
      token when is_binary(token) and token != "" ->
        {:ok, token}

      _ ->
        server_url = server_url(options, environment)

        with {:error, reason} <- stored_token(server_url, environment),
             do: provider_token(server_url, environment, reason, options)
    end
  end

  def reporting_token(options \\ []) do
    environment = Keyword.get(options, :environment, &System.get_env/1)

    if network_publishing_enabled?(options, environment) do
      server_url = server_url(options, environment)

      case environment.("TUIST_TOKEN") do
        nil ->
          case File.stat(credentials_path(server_url, environment)) do
            {:ok, _} ->
              stored_token(server_url, environment)

            {:error, :enoent} ->
              provider_or_network_token(server_url, environment)

            {:error, _} ->
              {:error,
               "Could not read Tuist credentials. Sign in again or deliberately remove them."}
          end

        token when is_binary(token) ->
          if String.trim(token) == "",
            do: {:error, "TUIST_TOKEN must not be blank"},
            else: {:ok, token}

        _ ->
          {:error, "Invalid TUIST_TOKEN"}
      end
    else
      __MODULE__.token(options)
    end
  end

  def network_publishing?(options) do
    environment = Keyword.get(options, :environment, &System.get_env/1)

    network_publishing_enabled?(options, environment) and
      __MODULE__.reporting_token(options) == {:ok, nil}
  end

  defp network_publishing_enabled?(options, environment) do
    case environment.("TUIST_NETWORK_TRUSTED_PUBLISHING") do
      nil ->
        Keyword.get(
          options,
          :network_trusted_publishing,
          Keyword.get(Config.project_tuist_config(options), :network_trusted_publishing, false)
        ) == true

      value ->
        value == "true"
    end
  end

  defp provider_or_network_token(server_url, environment) do
    supplied =
      Enum.any?(
        ~w(ACTIONS_ID_TOKEN_REQUEST_URL ACTIONS_ID_TOKEN_REQUEST_TOKEN
                            CIRCLE_OIDC_TOKEN_V2 CIRCLE_OIDC_TOKEN BITRISE_OIDC_ID_TOKEN
                            BITRISE_IDENTITY_TOKEN),
        &(not is_nil(environment.(&1)))
      )

    if supplied do
      case identity_token(environment) do
        {:ok, identity} -> exchange(server_url, identity)
        {:error, _} = error -> error
        :unsupported -> {:error, "Invalid OpenID Connect environment"}
      end
    else
      network_token(server_url)
    end
  end

  defp network_token(server_url) do
    host =
      server_url
      |> URI.parse()
      |> Map.fetch!(:host)
      |> String.downcase()
      |> String.trim_trailing(".")

    if host in ["tuist.dev", "tuist.io", "cloud.tuist.io", "cloud.tuist.dev"] or
         String.ends_with?(host, ".tuist.dev") or String.ends_with?(host, ".tuist.io") do
      {:error, "Credential-free publishing requires a configured self-hosted Tuist server URL."}
    else
      {:ok, nil}
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

    result =
      case identity_token(environment, options) do
        {:ok, identity_token} ->
          exchange(server_url, identity_token)

        :unsupported ->
          {:error, "OpenID Connect authentication supports GitHub Actions, CircleCI, and Bitrise"}

        {:error, message} ->
          {:error, message}
      end

    case result do
      {:ok, access} -> %{"accessToken" => access}
      {:error, message} -> Mix.raise(message)
    end
  end

  defp provider_token(server_url, environment, reason, options) do
    key = {__MODULE__, :provider_token, server_url}
    cached = :persistent_term.get(key, nil)

    if is_binary(cached) and not expired?(cached) do
      {:ok, cached}
    else
      case identity_token(environment, options) do
        {:ok, identity_token} ->
          with {:ok, access} <- exchange(server_url, identity_token) do
            :persistent_term.put(key, access)
            {:ok, access}
          end

        :unsupported ->
          {:error, reason}

        {:error, message} ->
          {:error, message}
      end
    end
  end

  defp exchange(server_url, identity_token) do
    case HTTP.request(:post, server_url <> "/api/auth/oidc/token", %{token: identity_token}) do
      {:ok, 200, %{"access_token" => access}} when is_binary(access) -> {:ok, access}
      response -> {:error, request_error("OpenID Connect authentication", response)}
    end
  end

  defp identity_token(environment, options) do
    cond do
      truthy?(environment.("GITHUB_ACTIONS")) ->
        github_identity_token(environment, Keyword.get(options, :sleep, &Process.sleep/1))

      truthy?(environment.("CIRCLECI")) ->
        present(
          environment.("CIRCLE_OIDC_TOKEN_V2") || environment.("CIRCLE_OIDC_TOKEN"),
          "CircleCI identity token is missing"
        )

      truthy?(environment.("BITRISE_IO")) ->
        present(
          environment.("BITRISE_OIDC_ID_TOKEN") || environment.("BITRISE_IDENTITY_TOKEN"),
          "Bitrise identity token is missing"
        )

      true ->
        :unsupported
    end
  end

  defp github_identity_token(environment, sleep) do
    with {:ok, request_url} <-
           present(
             environment.("ACTIONS_ID_TOKEN_REQUEST_URL"),
             "GitHub Actions requires id-token: write permission"
           ),
         {:ok, request_token} <-
           present(
             environment.("ACTIONS_ID_TOKEN_REQUEST_TOKEN"),
             "GitHub Actions requires id-token: write permission"
           ) do
      separator = if String.contains?(request_url, "?"), do: "&", else: "?"
      url = request_url <> separator <> "audience=tuist"
      request_github_identity_token(url, request_token, sleep, @github_identity_token_attempts)
    end
  end

  defp request_github_identity_token(url, request_token, sleep, attempts_left) do
    case HTTP.request(:get, url, nil, [{"authorization", "Bearer " <> request_token}]) do
      {:ok, 200, %{"value" => value}} when is_binary(value) ->
        {:ok, value}

      response ->
        if attempts_left > 1 and transient?(response) do
          sleep.(1_000 * 2 ** (@github_identity_token_attempts - attempts_left))
          request_github_identity_token(url, request_token, sleep, attempts_left - 1)
        else
          {:error, request_error("GitHub Actions identity token request", response)}
        end
    end
  end

  defp transient?({:ok, status, _}), do: status == 429 or status >= 500
  defp transient?({:error, _}), do: true

  defp present(value, _message) when is_binary(value) and value != "", do: {:ok, value}
  defp present(_value, message), do: {:error, message}

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
         %{"accessToken" => access} <- credentials,
         false <- Map.get(credentials, "rejected", false),
         true <- is_binary(access) and String.trim(access) != "" do
      if expired?(access) do
        Lock.with_lock(lock_path(server_url, environment), fn ->
          with {:ok, current} <- read(path),
               %{"accessToken" => token} <- current,
               false <- Map.get(current, "rejected", false),
               true <- is_binary(token) and String.trim(token) != "" do
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
      {:ok, 200, %{"access_token" => access, "refresh_token" => new_refresh}}
      when is_binary(access) and access != "" and is_binary(new_refresh) and new_refresh != "" ->
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
         {:ok, %{"exp" => expiration}} <- JSON.decode(decoded) do
      expiration <= System.system_time(:second) + 30
    else
      _ -> true
    end
  end

  defp read(path) do
    with {:ok, content} <- File.read(path), do: JSON.decode(content)
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
        :ok = IO.binwrite(file, JSON.encode!(credentials))
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

  defp request_error!(label, response), do: Mix.raise(request_error(label, response))

  defp request_error(label, {:ok, status, body}) do
    message =
      if is_map(body),
        do: Map.get(body, "message", "Unexpected response"),
        else: "Unexpected response"

    "#{label} failed (#{status}): #{message}"
  end

  defp request_error(label, {:error, reason}), do: "#{label} failed: #{inspect(reason)}"
end
