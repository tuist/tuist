defmodule TuistEx.Analytics.HTTPTest do
  use ExUnit.Case, async: false
  use Mimic

  alias TuistEx.Analytics.HTTP, as: AnalyticsHTTP
  alias TuistEx.Auth
  alias TuistEx.HTTP

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
      {:ok, 200, %{"id" => "run-id"}}
    end)

    assert :ok =
             AnalyticsHTTP.submit_test_run(%{id: "run-id", duration: 42},
               environment: environment
             )
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

  test "returns the config error when the project handle is missing" do
    environment = fn _ -> nil end
    stub(Auth, :token, fn _ -> {:ok, "token"} end)

    assert {:error, message} = AnalyticsHTTP.submit_test_run(%{}, environment: environment)
    assert message =~ "Missing Tuist project handle"
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
      {:ok, 201, %{"id" => "build-id"}}
    end)

    assert :ok = AnalyticsHTTP.submit_mix_build(%{id: "build-id"}, environment: environment)
  end
end
