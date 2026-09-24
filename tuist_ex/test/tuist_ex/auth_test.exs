defmodule TuistEx.AuthTest do
  use ExUnit.Case, async: false
  use Mimic

  alias TuistEx.{Auth, HTTP}

  defmodule ConfiguredProject do
    def project,
      do: [app: :configured, version: "0.1.0", tuist: [url: "https://configured.example"]]
  end

  setup do
    directory =
      Path.join(System.tmp_dir!(), "tuist-ex-auth-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(directory) end)

    environment = fn
      "XDG_CONFIG_HOME" -> Path.join(directory, "config")
      "XDG_STATE_HOME" -> Path.join(directory, "state")
      _ -> nil
    end

    %{directory: directory, environment: environment}
  end

  test "polls the browser device code and stores shared credentials", context do
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    expect(HTTP, :request, 2, fn :get, url ->
      assert url == "https://tuist.example/api/auth/device_code/device-code"

      Agent.get_and_update(calls, fn
        0 -> {{:ok, 202, %{}}, 1}
        1 -> {{:ok, 200, %{"access_token" => "access", "refresh_token" => "refresh"}}, 2}
      end)
    end)

    assert :ok =
             Auth.login(
               url: "https://tuist.example",
               environment: context.environment,
               device_code: fn -> "device-code" end,
               open_browser: fn url ->
                 assert url == "https://tuist.example/auth/device_codes/device-code?type=cli"
                 :ok
               end,
               sleep: fn 1_000 -> :ok end
             )

    assert credentials(context.directory) == %{
             "accessToken" => "access",
             "refreshToken" => "refresh"
           }

    refute File.exists?(lock_path(context.directory))
  end

  test "accepts email and password and prompts for a missing value", context do
    expect(HTTP, :request, fn :post, "https://tuist.example/api/auth", body ->
      assert body == %{email: "person@example.com", password: "secret"}
      {:ok, 200, %{"access_token" => "access", "refresh_token" => "refresh"}}
    end)

    assert :ok =
             Auth.login(
               url: "https://tuist.example",
               email: "person@example.com",
               environment: context.environment,
               prompt: fn :password -> "secret" end
             )

    assert credentials(context.directory)["refreshToken"] == "refresh"
  end

  test "continues browser login when a browser cannot be opened", context do
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    expect(HTTP, :request, 3, fn :get, _url ->
      Agent.get_and_update(calls, fn
        0 -> {{:error, :timeout}, 1}
        1 -> {{:ok, 503, %{}}, 2}
        2 -> {{:ok, 200, %{"access_token" => "access", "refresh_token" => "refresh"}}, 3}
      end)
    end)

    assert :ok =
             Auth.login(
               url: "https://tuist.example",
               environment: context.environment,
               device_code: fn -> "device-code" end,
               open_browser: fn _ -> {:error, "unavailable"} end,
               sleep: fn 1_000 -> :ok end
             )

    assert Agent.get(calls, & &1) == 3
    assert credentials(context.directory)["accessToken"] == "access"
  end

  test "uses the Tuist configuration home before the standard home", context do
    environment = fn
      "TUIST_XDG_CONFIG_HOME" -> Path.join(context.directory, "tuist-config")
      "TUIST_XDG_STATE_HOME" -> Path.join(context.directory, "tuist-state")
      key -> context.environment.(key)
    end

    expect(HTTP, :request, fn :post, "https://tuist.example/api/auth", _ ->
      {:ok, 200, %{"access_token" => "access", "refresh_token" => "refresh"}}
    end)

    assert :ok =
             Auth.login(
               url: "https://tuist.example",
               email: "person@example.com",
               password: "secret",
               environment: environment
             )

    path = Path.join(context.directory, "tuist-config/tuist/credentials/tuist.example.json")
    assert File.exists?(path)
    assert {:ok, directory_stat} = File.stat(Path.dirname(path))
    assert {:ok, file_stat} = File.stat(path)
    assert Bitwise.band(directory_stat.mode, 0o777) == 0o700
    assert Bitwise.band(file_stat.mode, 0o777) == 0o600

    refute File.exists?(
             Path.join(context.directory, "config/tuist/credentials/tuist.example.json")
           )

    refute File.exists?(
             Path.join(
               context.directory,
               "tuist-state/tuist/auth-locks/token_https___tuist.example.lock"
             )
           )
  end

  test "exchanges a provider identity token in continuous integration", context do
    environment = fn
      "CI" -> "true"
      "CIRCLECI" -> "true"
      "CIRCLE_OIDC_TOKEN_V2" -> "identity"
      key -> context.environment.(key)
    end

    expect(HTTP, :request, fn :post, "https://tuist.example/api/auth/oidc/token", body ->
      assert body == %{token: "identity"}
      {:ok, 200, %{"access_token" => "access"}}
    end)

    assert :ok = Auth.login(url: "https://tuist.example", environment: environment)
    assert credentials(context.directory) == %{"accessToken" => "access"}
  end

  test "requests a GitHub Actions identity token for the Tuist audience", context do
    environment = fn
      "GITHUB_ACTIONS" -> "true"
      "ACTIONS_ID_TOKEN_REQUEST_URL" -> "https://actions.example/token?job=1"
      "ACTIONS_ID_TOKEN_REQUEST_TOKEN" -> "request-token"
      key -> context.environment.(key)
    end

    expect(HTTP, :request, fn :get,
                              "https://actions.example/token?job=1&audience=tuist",
                              nil,
                              [{"authorization", "Bearer request-token"}] ->
      {:ok, 200, %{"value" => "identity"}}
    end)

    expect(HTTP, :request, fn :post, "https://tuist.example/api/auth/oidc/token", body ->
      assert body == %{token: "identity"}
      {:ok, 200, %{"access_token" => "access"}}
    end)

    assert :ok = Auth.login(url: "https://tuist.example", environment: environment)
    assert credentials(context.directory) == %{"accessToken" => "access"}
  end

  test "environment server address takes precedence over the command option", context do
    environment = fn
      "TUIST_URL" -> "https://tuist.example"
      key -> context.environment.(key)
    end

    expect(HTTP, :request, fn :post, "https://tuist.example/api/auth", _ ->
      {:ok, 200, %{"access_token" => "access", "refresh_token" => "refresh"}}
    end)

    assert :ok =
             Auth.login(
               url: "https://ignored.example",
               email: "a",
               password: "b",
               environment: environment
             )
  end

  test "reads a shared server address from mix.exs", context do
    Mix.Project.push(ConfiguredProject)

    try do
      expect(HTTP, :request, fn :post, "https://configured.example/api/auth", _ ->
        {:ok, 200, %{"access_token" => "access", "refresh_token" => "refresh"}}
      end)

      assert :ok = Auth.login(email: "a", password: "b", environment: context.environment)

      assert File.exists?(
               Path.join(context.directory, "config/tuist/credentials/configured.example.json")
             )
    after
      Mix.Project.pop()
    end
  end

  test "rereads credentials after waiting for the refresh lock", context do
    path = Path.join(context.directory, "config/tuist/credentials/tuist.example.json")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(%{"accessToken" => jwt(0), "refreshToken" => "old"}))

    parent = self()

    holder =
      Task.async(fn ->
        TuistEx.Lock.with_lock(lock_path(context.directory), fn ->
          send(parent, :locked)

          receive do
            :release -> File.write!(path, Jason.encode!(%{"accessToken" => jwt(4_000_000_000)}))
          end
        end)
      end)

    assert_receive :locked

    reader =
      Task.async(fn ->
        Auth.token(url: "https://tuist.example", environment: context.environment)
      end)

    send(holder.pid, :release)

    assert {:ok, token} = Task.await(reader)
    assert token == jwt(4_000_000_000)
    assert :ok = Task.await(holder)
  end

  test "reports a refresh network failure without marking the session expired", context do
    path = Path.join(context.directory, "config/tuist/credentials/tuist.example.json")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(%{"accessToken" => jwt(0), "refreshToken" => "refresh"}))

    expect(HTTP, :request, fn :post, "https://tuist.example/api/auth/refresh_token", body ->
      assert body == %{refresh_token: "refresh"}
      {:error, :timeout}
    end)

    assert {:error, "Token refresh failed: :timeout"} =
             Auth.token(url: "https://tuist.example", environment: context.environment)
  end

  defp jwt(expiration) do
    payload = %{exp: expiration} |> Jason.encode!() |> Base.url_encode64(padding: false)
    "header.#{payload}.signature"
  end

  defp credentials(directory) do
    directory
    |> Path.join("config/tuist/credentials/tuist.example.json")
    |> File.read!()
    |> Jason.decode!()
  end

  defp lock_path(directory) do
    Path.join(directory, "state/tuist/auth-locks/token_https___tuist.example.lock")
  end
end
