defmodule TuistEx.Analytics.HTTPTest do
  use ExUnit.Case, async: true
  use Mimic

  alias TuistEx.Analytics.HTTP, as: AnalyticsHTTP
  alias TuistEx.Auth
  alias TuistEx.HTTP

  setup do
    stub(Auth, :reporting_token, fn options -> Auth.token(options) end)
    :ok
  end

  test "POSTs the payload to /api/projects/:acc/:proj/tests with a bearer token" do
    environment = fn
      "TUIST_URL" -> "https://tuist.example"
      "TUIST_PROJECT" -> "acme/widgets"
      _ -> nil
    end

    expect(Auth, :token, fn opts ->
      assert Keyword.get(opts, :environment) == environment
      {:ok, "access-token"}
    end)

    expect(HTTP, :request, fn :post, url, body, headers ->
      assert url == "https://tuist.example/api/projects/acme/widgets/tests"
      assert body == %{id: "run-id", duration: 42}
      assert {"authorization", "Bearer access-token"} in headers
      assert {"x-tuist-actor-id", "developer-123"} in headers
      {:ok, 200, %{"id" => "run-id"}}
    end)

    assert :ok =
             AnalyticsHTTP.submit_test_run(%{id: "run-id", duration: 42},
               environment: environment,
               actor_id: "developer-123"
             )
  end

  test "build and test reports omit actor headers by default despite operating-system usernames" do
    environment = fn
      "TUIST_URL" -> "https://tuist.example"
      "TUIST_PROJECT" -> "acme/widgets"
      "USER" -> "developer"
      "USERNAME" -> "windows-user"
      "LOGNAME" -> "legacy-user"
      _ -> nil
    end

    stub(Auth, :token, fn _ -> {:ok, "existing-token"} end)

    expect(HTTP, :request, 2, fn :post, _url, body, headers ->
      assert body == %{id: "report-id"}
      assert headers == [{"authorization", "Bearer existing-token"}]
      {:ok, 200, %{"id" => "report-id"}}
    end)

    for suffix <- ["/tests", "/mix/builds"] do
      assert {:ok, %{"id" => "report-id"}} =
               AnalyticsHTTP.project_request(:post, suffix, %{id: "report-id"},
                 environment: environment,
                 project_config: []
               )
    end
  end

  test "surfaces HTTP failures as {:error, {:http, status, body}}" do
    environment = fn
      "TUIST_URL" -> "https://tuist.example"
      "TUIST_PROJECT" -> "acme/widgets"
      _ -> nil
    end

    stub(Auth, :token, fn _ -> {:ok, "token"} end)

    expect(HTTP, :request, fn _method, _url, _body, _headers ->
      {:ok, 500, %{"message" => "boom"}}
    end)

    assert {:error, {:http, 500, %{"message" => "boom"}}} =
             AnalyticsHTTP.submit_test_run(%{id: "x"}, environment: environment)
  end

  test "actor headers never reach shard planning" do
    environment = fn
      "TUIST_URL" -> "https://tuist.example"
      "TUIST_PROJECT" -> "acme/widgets"
      "USER" -> "developer"
      _ -> nil
    end

    stub(Auth, :token, fn _ -> {:ok, "token"} end)

    expect(HTTP, :request, fn :post, url, _body, headers ->
      assert url == "https://tuist.example/api/projects/acme/widgets/tests/shards"
      refute Enum.any?(headers, fn {name, _} -> name == "x-tuist-actor-id" end)
      {:ok, 200, %{}}
    end)

    assert {:ok, %{}} =
             AnalyticsHTTP.project_request(:post, "/tests/shards", %{},
               environment: environment,
               actor_id: "developer-123"
             )
  end

  test "actor claims never replace missing authentication" do
    environment = fn
      "TUIST_URL" -> "https://tuist.example"
      "TUIST_PROJECT" -> "acme/widgets"
      "TUIST_ACTOR_ID" -> "employee-123"
      _ -> nil
    end

    stub(Auth, :token, fn _ -> {:error, "not authenticated"} end)
    reject(HTTP, :request, 4)

    assert {:error, "not authenticated"} =
             AnalyticsHTTP.submit_test_run(%{id: "run-id"}, environment: environment)

    assert {:error, "not authenticated"} =
             AnalyticsHTTP.submit_mix_build(%{id: "build-id"}, environment: environment)
  end

  test "reads and uploads omit actor headers and preserve authentication" do
    environment = fn
      "TUIST_URL" -> "https://tuist.example"
      "TUIST_PROJECT" -> "acme/widgets"
      "TUIST_ACTOR_ID" -> "employee-123"
      _ -> nil
    end

    stub(Auth, :token, fn _ -> {:ok, "existing-token"} end)

    expect(HTTP, :request, 2, fn _method, _url, _body, headers ->
      assert headers == [{"authorization", "Bearer existing-token"}]
      {:ok, 200, %{}}
    end)

    assert {:ok, %{}} =
             AnalyticsHTTP.project_request(:get, "/tests", nil, environment: environment)

    assert {:ok, %{}} =
             AnalyticsHTTP.project_request(:post, "/tests/coverage/uploads", %{},
               environment: environment
             )
  end

  test "returns the config error when the project handle is missing" do
    environment = fn _ -> nil end
    stub(Auth, :token, fn _ -> {:ok, "token"} end)

    assert {:error, message} = AnalyticsHTTP.submit_test_run(%{}, environment: environment)
    assert message =~ "Missing Tuist project handle"
  end

  for message <- [
        "The dependency cache data is invalid.",
        "Invalid value for enum",
        "Invalid value for enum\nInvalid value for enum"
      ] do
    @tag rejection_message: message
    test "retries a rejected current-hit report once after #{inspect(message)}", %{
      rejection_message: message
    } do
      {payload, legacy} = mix_payloads()
      options = mix_options()
      stub(Auth, :token, fn _ -> {:ok, "token"} end)

      expect(HTTP, :request, fn :post, url, body, headers ->
        assert String.ends_with?(url, "/mix/builds")
        assert body == payload
        assert {"authorization", "Bearer token"} in headers
        {:ok, 400, %{"message" => message}}
      end)

      expect(HTTP, :request, fn :post, _url, body, headers ->
        assert body == legacy
        assert {"authorization", "Bearer token"} in headers
        {:ok, 201, %{"id" => payload.id}}
      end)

      assert :ok = AnalyticsHTTP.submit_mix_build(payload, options)
    end
  end

  test "string-keyed reports preserve every other field when falling back" do
    {payload, legacy} = mix_payloads()
    payload = payload |> JSON.encode!() |> JSON.decode!()
    legacy = legacy |> JSON.encode!() |> JSON.decode!()
    stub(Auth, :token, fn _ -> {:ok, "token"} end)

    expect(HTTP, :request, fn :post, _url, body, _headers ->
      assert body == payload
      {:ok, 400, %{"message" => "Invalid value for enum"}}
    end)

    expect(HTTP, :request, fn :post, _url, body, _headers ->
      assert body == legacy
      {:ok, 201, %{"id" => "build-id"}}
    end)

    assert :ok = AnalyticsHTTP.submit_mix_build(payload, mix_options())
  end

  test "an accepting server receives the complete report without a retry" do
    {payload, _legacy} = mix_payloads()
    stub(Auth, :token, fn _ -> {:ok, "token"} end)

    expect(HTTP, :request, fn :post, _url, body, _headers ->
      assert body == payload
      {:ok, 201, %{"id" => payload.id}}
    end)

    assert :ok = AnalyticsHTTP.submit_mix_build(payload, mix_options())
  end

  test "a reuse-only report falls back to unavailable observations without inventing a cache hit" do
    {payload, _legacy} = mix_payloads()

    payload = %{
      payload
      | files: [],
        diagnostics: [],
        steps: [],
        dependency_cache: [hd(payload.dependency_cache)]
    }

    stub(Auth, :token, fn _ -> {:ok, "token"} end)

    expect(HTTP, :request, fn :post, _url, body, _headers ->
      assert body == payload
      {:ok, 400, %{"message" => "Invalid value for enum"}}
    end)

    expect(HTTP, :request, fn :post, _url, body, _headers ->
      assert body == %{payload | dependency_cache: []}
      {:ok, 201, %{"id" => payload.id}}
    end)

    assert :ok = AnalyticsHTTP.submit_mix_build(payload, mix_options())
  end

  test "transport errors are not retried even when the report contains current hits" do
    {payload, _legacy} = mix_payloads()
    stub(Auth, :token, fn _ -> {:ok, "token"} end)

    expect(HTTP, :request, fn :post, _url, body, _headers ->
      assert body == payload
      {:error, :timeout}
    end)

    assert {:error, :timeout} = AnalyticsHTTP.submit_mix_build(payload, mix_options())
  end

  test "a rejected fallback surfaces the error without a third request" do
    {payload, legacy} = mix_payloads()
    stub(Auth, :token, fn _ -> {:ok, "token"} end)
    rejection = %{"message" => "The dependency cache data is invalid."}

    expect(HTTP, :request, fn :post, _url, body, _headers ->
      assert body == payload
      {:ok, 400, rejection}
    end)

    expect(HTTP, :request, fn :post, _url, body, _headers ->
      assert body == legacy
      {:ok, 400, rejection}
    end)

    assert {:error, {:http, 400, ^rejection}} =
             AnalyticsHTTP.submit_mix_build(payload, mix_options())
  end

  test "an enumeration error on a retained field is not masked by the fallback" do
    {payload, legacy} = mix_payloads()
    payload = Map.put(payload, :status, "invalid")
    legacy = Map.put(legacy, :status, "invalid")
    stub(Auth, :token, fn _ -> {:ok, "token"} end)
    rejection = %{"message" => "Invalid value for enum"}

    expect(HTTP, :request, fn :post, _url, body, _headers ->
      assert body == payload
      {:ok, 400, rejection}
    end)

    expect(HTTP, :request, fn :post, _url, body, _headers ->
      assert body == legacy
      {:ok, 400, rejection}
    end)

    assert {:error, {:http, 400, ^rejection}} =
             AnalyticsHTTP.submit_mix_build(payload, mix_options())
  end

  test "validation failures without current-hit observations are not retried" do
    {_payload, legacy} = mix_payloads()
    stub(Auth, :token, fn _ -> {:ok, "token"} end)
    rejection = %{"message" => "Invalid value for enum"}

    expect(HTTP, :request, fn :post, _url, body, _headers ->
      assert body == legacy
      {:ok, 400, rejection}
    end)

    assert {:error, {:http, 400, ^rejection}} =
             AnalyticsHTTP.submit_mix_build(legacy, mix_options())
  end

  for {status, body} <- [
        {400, %{"message" => "The custom metadata is invalid."}},
        {400, %{"message" => "A number in the request is out of range."}},
        {401, %{"message" => "The dependency cache data is invalid."}},
        {403, %{"message" => "Invalid value for enum"}},
        {422, %{"message" => "Invalid value for enum"}},
        {429, %{"message" => "The dependency cache data is invalid."}},
        {500, %{"message" => "The dependency cache data is invalid."}}
      ] do
    @tag response: {status, body}
    test "does not retry unrelated failure #{status} #{inspect(body)}", %{
      response: {status, body}
    } do
      {payload, _legacy} = mix_payloads()
      stub(Auth, :token, fn _ -> {:ok, "token"} end)

      expect(HTTP, :request, fn :post, _url, received, _headers ->
        assert received == payload
        {:ok, status, body}
      end)

      assert {:error, {:http, ^status, ^body}} =
               AnalyticsHTTP.submit_mix_build(payload, mix_options())
    end
  end

  defp mix_options do
    [
      environment: fn
        "TUIST_URL" -> "https://tuist.example"
        "TUIST_PROJECT" -> "acme/widgets"
        _ -> nil
      end
    ]
  end

  defp mix_payloads do
    events = [
      %{
        dependency: "current",
        outcome: "local_hit",
        reason: "up_to_date",
        key: "",
        duration_ms: 1
      },
      %{
        dependency: "compiled",
        outcome: "miss",
        reason: "",
        key: String.duplicate("a", 64),
        duration_ms: 10
      },
      %{
        dependency: "restored",
        outcome: "local_hit",
        reason: "",
        key: String.duplicate("b", 64),
        duration_ms: 2
      },
      %{
        dependency: "native",
        outcome: "bypass",
        reason: "custom_compiler",
        key: "",
        duration_ms: 3
      }
    ]

    payload = %{
      id: "build-id",
      contract_version: "0.2",
      files: [%{path: "lib/app.ex", compile_duration_ms: 12}],
      diagnostics: [%{severity: "warning", message: "example"}],
      steps: [%{category: "compiler", title: "Elixir", duration_ms: 12}],
      dependency_cache: events
    }

    {payload, %{payload | dependency_cache: tl(events)}}
  end

  test "submit_mix_build/2 POSTs to /mix/builds with the same auth path" do
    environment = fn
      "TUIST_URL" -> "https://tuist.example"
      "TUIST_PROJECT" -> "acme/widgets"
      _ -> nil
    end

    stub(Auth, :token, fn _ -> {:ok, "token"} end)

    expect(HTTP, :request, fn :post, url, body, headers ->
      assert url == "https://tuist.example/api/projects/acme/widgets/mix/builds"
      assert body == %{id: "build-id"}
      assert {"authorization", "Bearer token"} in headers
      assert {"x-tuist-actor-id", "developer-123"} in headers
      {:ok, 201, %{"id" => "build-id"}}
    end)

    assert :ok =
             AnalyticsHTTP.submit_mix_build(%{id: "build-id"},
               environment: environment,
               actor_id: "developer-123"
             )
  end
end
