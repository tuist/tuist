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

    for account <- [nil, "first-account", "second-account"] do
      key = {Auth, :provider_token, "https://tuist.example", account}
      :persistent_term.erase(key)
      on_exit(fn -> :persistent_term.erase(key) end)
    end

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

  test "prefers a supplied workload token over provider detection", context do
    environment = fn
      "TUIST_OIDC_TOKEN" -> "  fly-identity-token\n"
      "GITHUB_ACTIONS" -> "true"
      key -> context.environment.(key)
    end

    expect(HTTP, :request, fn :post, "https://tuist.example/api/auth/oidc/token", body ->
      assert body == %{token: "fly-identity-token"}
      {:ok, 200, %{"access_token" => "access"}}
    end)

    assert :ok = Auth.login(url: "https://tuist.example", environment: environment)
    assert credentials(context.directory) == %{"accessToken" => "access"}
  end

  test "logs in with a supplied workload token without CI provider variables", context do
    environment = fn
      "TUIST_OIDC_TOKEN" -> "fly-identity-token"
      key -> context.environment.(key)
    end

    expect(HTTP, :request, fn :post,
                              "https://tuist.example/api/auth/oidc/token",
                              %{token: "fly-identity-token"} ->
      {:ok, 200, %{"access_token" => "access"}}
    end)

    assert :ok = Auth.login(url: "https://tuist.example", environment: environment)
    assert credentials(context.directory) == %{"accessToken" => "access"}
  end

  test "supplied workload login forwards the target Tuist account", context do
    environment = fn
      "TUIST_OIDC_TOKEN" -> "fly-identity-token"
      "TUIST_OIDC_ACCOUNT" -> " first-account \n"
      key -> context.environment.(key)
    end

    expect(HTTP, :request, fn :post, "https://tuist.example/api/auth/oidc/token", body ->
      assert body == %{token: "fly-identity-token", account_handle: "first-account"}
      {:ok, 200, %{"access_token" => "access"}}
    end)

    assert :ok = Auth.login(url: "https://tuist.example", environment: environment)
  end

  test "blank account selectors do not break existing CI authentication", context do
    for account <- ["", " \n "] do
      environment = fn
        "TUIST_OIDC_ACCOUNT" -> account
        "CIRCLECI" -> "true"
        "CIRCLE_OIDC_TOKEN_V2" -> "identity"
        key -> context.environment.(key)
      end

      expect(HTTP, :request, fn :post, "https://tuist.example/api/auth/oidc/token", body ->
        assert body == %{token: "identity"}
        {:ok, 200, %{"access_token" => "access"}}
      end)

      assert :ok = Auth.login(url: "https://tuist.example", environment: environment)
    end
  end

  test "a warm workload session does not hide an explicitly blank identity", context do
    access = jwt(System.os_time(:second) + 3600)

    expect(HTTP, :request, fn :post, _url, %{token: "first-identity"} ->
      {:ok, 200, %{"access_token" => access}}
    end)

    assert {:ok, ^access} =
             Auth.token(automatic_options(context, %{"TUIST_OIDC_TOKEN" => "first-identity"}))

    for blank <- ["", " \n\t"] do
      assert {:error, message} =
               Auth.token(automatic_options(context, %{"TUIST_OIDC_TOKEN" => blank}))

      assert message =~ "TUIST_OIDC_TOKEN is empty"
    end
  end

  test "changing a supplied identity replaces the single cached session", context do
    expiration = System.os_time(:second) + 3600
    tokens = %{"first-identity" => jwt(expiration), "second-identity" => jwt(expiration + 1)}

    expect(HTTP, :request, 3, fn :post, _url, %{token: identity} ->
      {:ok, 200, %{"access_token" => Map.fetch!(tokens, identity)}}
    end)

    for identity <- ["first-identity", "second-identity", " second-identity\n", "first-identity"] do
      access = tokens[String.trim(identity)]

      assert {:ok, ^access} =
               Auth.token(automatic_options(context, %{"TUIST_OIDC_TOKEN" => identity}))

      assert {{:supplied, fingerprint}, ^access} =
               :persistent_term.get({Auth, :provider_token, "https://tuist.example", nil})

      assert fingerprint == :crypto.hash(:sha256, String.trim(identity))
    end
  end

  test "a rejected identity cannot reuse an earlier workload session", context do
    access = jwt(System.os_time(:second) + 3600)

    expect(HTTP, :request, 2, fn :post, _url, %{token: identity} ->
      if identity == "valid-identity",
        do: {:ok, 200, %{"access_token" => access}},
        else: {:ok, 401, %{"message" => "Rejected identity"}}
    end)

    assert {:ok, ^access} =
             Auth.token(automatic_options(context, %{"TUIST_OIDC_TOKEN" => "valid-identity"}))

    assert {:error, message} =
             Auth.token(automatic_options(context, %{"TUIST_OIDC_TOKEN" => "rejected-identity"}))

    assert message =~ "Rejected identity"

    assert {:ok, ^access} =
             Auth.token(automatic_options(context, %{"TUIST_OIDC_TOKEN" => "valid-identity"}))
  end

  test "switching identity sources exchanges again but reuses an unchanged GitHub session",
       context do
    expiration = System.os_time(:second) + 3600
    tokens = %{"workload-identity" => jwt(expiration), "github-identity" => jwt(expiration + 1)}

    expect(HTTP, :request, fn :get,
                              "https://github.example/token?audience=tuist",
                              nil,
                              [{"authorization", "Bearer github-request"}] ->
      {:ok, 200, %{"value" => "github-identity"}}
    end)

    expect(HTTP, :request, 3, fn :post, _url, %{token: identity} ->
      {:ok, 200, %{"access_token" => Map.fetch!(tokens, identity)}}
    end)

    for source <- [:supplied, :github, :github, :supplied, :supplied] do
      values = %{
        "TUIST_OIDC_TOKEN" => if(source == :supplied, do: "workload-identity"),
        "GITHUB_ACTIONS" => "true",
        "ACTIONS_ID_TOKEN_REQUEST_URL" => "https://github.example/token",
        "ACTIONS_ID_TOKEN_REQUEST_TOKEN" => "github-request"
      }

      access = tokens[if(source == :supplied, do: "workload-identity", else: "github-identity")]
      assert {:ok, ^access} = Auth.token(automatic_options(context, values))
    end
  end

  test "automatic workload exchanges and caches are scoped to the selected account", context do
    expiration = System.os_time(:second) + 3600
    tokens = %{"first-account" => jwt(expiration), "second-account" => jwt(expiration + 1)}

    expect(HTTP, :request, 2, fn :post, "https://tuist.example/api/auth/oidc/token", body ->
      assert body.token == "fly-identity-token"
      {:ok, 200, %{"access_token" => Map.fetch!(tokens, body.account_handle)}}
    end)

    for account <- ["first-account", "second-account", "first-account"] do
      environment = fn
        "TUIST_OIDC_TOKEN" -> "fly-identity-token"
        "TUIST_OIDC_ACCOUNT" -> account
        key -> context.environment.(key)
      end

      expected = Map.fetch!(tokens, account)
      assert {:ok, ^expected} = Auth.token(url: "https://tuist.example", environment: environment)
    end
  end

  test "automatic token exchange accepts workload identities without persisting them", context do
    environment = fn
      "TUIST_OIDC_TOKEN" -> "fly-identity-token"
      key -> context.environment.(key)
    end

    expect(HTTP, :request, fn :post,
                              "https://tuist.example/api/auth/oidc/token",
                              %{token: "fly-identity-token"} ->
      {:ok, 200, %{"access_token" => "access"}}
    end)

    assert {:ok, "access"} = Auth.token(url: "https://tuist.example", environment: environment)

    refute File.exists?(
             Path.join(context.directory, "config/tuist/credentials/tuist.example.json")
           )
  end

  test "rejects empty supplied tokens without falling back to browser or provider authentication",
       context do
    reject(HTTP, :request, 3)

    for value <- ["", " \n\t"] do
      environment = fn
        "TUIST_OIDC_TOKEN" -> value
        "CIRCLECI" -> "true"
        key -> context.environment.(key)
      end

      assert_raise Mix.Error, ~r/TUIST_OIDC_TOKEN is empty/, fn ->
        Auth.login(url: "https://tuist.example", environment: environment)
      end

      assert {:error, message} =
               Auth.token(url: "https://tuist.example", environment: environment)

      assert message =~ "TUIST_OIDC_TOKEN is empty"
    end
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
    File.write!(path, JSON.encode!(%{"accessToken" => jwt(0), "refreshToken" => "old"}))

    parent = self()

    holder =
      Task.async(fn ->
        TuistEx.Lock.with_lock(lock_path(context.directory), fn ->
          send(parent, :locked)

          receive do
            :release ->
              # Replaced in one step, as the real refresh does: a plain write
              # empties the file first, and the reader below may look at it
              # in that instant and find no credentials.
              File.write!(path <> ".tmp", JSON.encode!(%{"accessToken" => jwt(4_000_000_000)}))
              File.rename!(path <> ".tmp", path)
          end
        end)
      end)

    assert_receive :locked, 5_000

    reader =
      Task.async(fn ->
        Auth.token(url: "https://tuist.example", environment: context.environment)
      end)

    send(holder.pid, :release)

    assert {:ok, token} = Task.await(reader)
    assert token == jwt(4_000_000_000)
    assert :ok = Task.await(holder)
  end

  test "exchanges a continuous integration identity token without a login and reuses it",
       context do
    environment = circleci(context)
    access = jwt(4_000_000_000)

    expect(HTTP, :request, fn :post, "https://tuist.example/api/auth/oidc/token", body ->
      assert body == %{token: "identity"}
      {:ok, 200, %{"access_token" => access}}
    end)

    assert {:ok, ^access} = Auth.token(url: "https://tuist.example", environment: environment)
    assert {:ok, ^access} = Auth.token(url: "https://tuist.example", environment: environment)
    refute File.exists?(Path.join(context.directory, "config/tuist/credentials"))
  end

  test "exchanges the identity token again once the exchanged token expires", context do
    environment = circleci(context)
    {:ok, calls} = Agent.start_link(fn -> [jwt(0), jwt(4_000_000_000)] end)

    expect(HTTP, :request, 2, fn :post, "https://tuist.example/api/auth/oidc/token", _ ->
      {:ok, 200,
       %{"access_token" => Agent.get_and_update(calls, fn [next | rest] -> {next, rest} end)}}
    end)

    assert {:ok, expired} = Auth.token(url: "https://tuist.example", environment: environment)
    assert expired == jwt(0)
    assert {:ok, fresh} = Auth.token(url: "https://tuist.example", environment: environment)
    assert fresh == jwt(4_000_000_000)
  end

  test "exchanges the identity token when stored credentials expired without a refresh token",
       context do
    path = Path.join(context.directory, "config/tuist/credentials/tuist.example.json")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, JSON.encode!(%{"accessToken" => jwt(0)}))

    expect(HTTP, :request, fn :post, "https://tuist.example/api/auth/oidc/token", _ ->
      {:ok, 200, %{"access_token" => "access"}}
    end)

    assert {:ok, "access"} =
             Auth.token(url: "https://tuist.example", environment: circleci(context))
  end

  test "returns the login hint without a request outside continuous integration", context do
    reject(&HTTP.request/3)
    reject(&HTTP.request/4)

    assert {:error, "Run `mix tuist.login` or set TUIST_TOKEN"} =
             Auth.token(url: "https://tuist.example", environment: context.environment)
  end

  test "retries the GitHub Actions identity token request on transient failures", context do
    {:ok, attempts} = Agent.start_link(fn -> [{:ok, 503, %{}}, {:error, :timeout}] end)

    expect(HTTP, :request, 3, fn :get, "https://actions.example/token?audience=tuist", nil, _ ->
      Agent.get_and_update(attempts, fn
        [response | rest] -> {response, rest}
        [] -> {{:ok, 200, %{"value" => "identity"}}, []}
      end)
    end)

    expect(HTTP, :request, fn :post, "https://tuist.example/api/auth/oidc/token", body ->
      assert body == %{token: "identity"}
      {:ok, 200, %{"access_token" => "access"}}
    end)

    test_pid = self()

    assert {:ok, "access"} =
             Auth.token(
               url: "https://tuist.example",
               environment: github_actions(context),
               sleep: &send(test_pid, {:slept, &1})
             )

    assert_received {:slept, 1_000}
    assert_received {:slept, 2_000}
  end

  test "gives up on the GitHub Actions identity token request after repeated failures",
       context do
    expect(HTTP, :request, 5, fn :get, "https://actions.example/token?audience=tuist", nil, _ ->
      {:ok, 503, %{}}
    end)

    assert {:error, "GitHub Actions identity token request failed (503): Unexpected response"} =
             Auth.token(
               url: "https://tuist.example",
               environment: github_actions(context),
               sleep: fn _ -> :ok end
             )
  end

  test "does not retry the GitHub Actions identity token request on client errors", context do
    expect(HTTP, :request, fn :get, "https://actions.example/token?audience=tuist", nil, _ ->
      {:ok, 403, %{"message" => "Forbidden"}}
    end)

    assert {:error, "GitHub Actions identity token request failed (403): Forbidden"} =
             Auth.token(
               url: "https://tuist.example",
               environment: github_actions(context),
               sleep: fn _ -> flunk("unexpected retry") end
             )
  end

  test "returns an error instead of raising when GitHub Actions withholds the identity token",
       context do
    reject(&HTTP.request/4)

    environment = fn
      "GITHUB_ACTIONS" -> "true"
      key -> context.environment.(key)
    end

    assert {:error, "GitHub Actions requires id-token: write permission"} =
             Auth.token(url: "https://tuist.example", environment: environment)
  end

  test "returns an error instead of raising when the server refuses the identity token",
       context do
    expect(HTTP, :request, fn :post, "https://tuist.example/api/auth/oidc/token", _ ->
      {:ok, 403, %{"message" => "No project is connected to this repository"}}
    end)

    assert {:error,
            "OpenID Connect authentication failed (403): No project is connected to this repository"} =
             Auth.token(url: "https://tuist.example", environment: circleci(context))
  end

  test "reports a refresh network failure without marking the session expired", context do
    path = Path.join(context.directory, "config/tuist/credentials/tuist.example.json")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, JSON.encode!(%{"accessToken" => jwt(0), "refreshToken" => "refresh"}))

    expect(HTTP, :request, fn :post, "https://tuist.example/api/auth/refresh_token", body ->
      assert body == %{refresh_token: "refresh"}
      {:error, :timeout}
    end)

    assert {:error, "Token refresh failed: :timeout"} =
             Auth.token(url: "https://tuist.example", environment: context.environment)
  end

  defp circleci(context) do
    fn
      "CIRCLECI" -> "true"
      "CIRCLE_OIDC_TOKEN_V2" -> "identity"
      key -> context.environment.(key)
    end
  end

  defp github_actions(context) do
    fn
      "GITHUB_ACTIONS" -> "true"
      "ACTIONS_ID_TOKEN_REQUEST_URL" -> "https://actions.example/token"
      "ACTIONS_ID_TOKEN_REQUEST_TOKEN" -> "request-token"
      key -> context.environment.(key)
    end
  end

  defp automatic_options(context, values) do
    [
      url: "https://tuist.example",
      environment: fn key -> Map.get(values, key, context.environment.(key)) end
    ]
  end

  defp jwt(expiration) do
    payload = %{exp: expiration} |> JSON.encode!() |> Base.url_encode64(padding: false)
    "header.#{payload}.signature"
  end

  defp credentials(directory) do
    directory
    |> Path.join("config/tuist/credentials/tuist.example.json")
    |> File.read!()
    |> JSON.decode!()
  end

  defp lock_path(directory) do
    Path.join(directory, "state/tuist/auth-locks/token_https___tuist.example.lock")
  end
end
