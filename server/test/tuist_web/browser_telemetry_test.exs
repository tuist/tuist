defmodule TuistWeb.BrowserTelemetryTest do
  use ExUnit.Case, async: true

  alias TuistWeb.BrowserTelemetry.Enrichment

  defp payload(url) do
    %{
      "meta" => %{
        "page" => %{"url" => url},
        "session" => %{"id" => "session-1"},
        "view" => %{"name" => "marketing"}
      },
      "measurements" => [
        %{"type" => "web-vitals", "values" => %{"lcp" => 3200}, "context" => %{"navigation_entry_id" => "nav-1"}}
      ]
    }
  end

  defp enrich(payload, authentication \\ "anonymous") do
    Enrichment.enrich(payload, authentication, "a3e837c27a56c4cf-SEA", "https://tuist.dev", "prod")
  end

  test "classifies the reported URL using router metadata, ignoring forged view names and query strings" do
    for {path, surface} <- [
          {"/", "marketing"},
          {"/en/docs", "docs"},
          {"/users/log_in?return_to=%2Fen%2Fdocs", "auth"},
          {"/docs/login", "auth"},
          {"/turnstile-challenge", "challenge"},
          {"/api/docs", "api_docs"},
          {"/tuist/tuist", "dashboard_anonymous"}
        ] do
      assert {:ok, result} = enrich(payload("https://tuist.dev" <> path))
      assert hd(result["measurements"])["context"]["rum_surface"] == surface
    end

    assert {:ok, result} = enrich(payload("https://tuist.dev/tuist/tuist"), "authenticated")
    assert hd(result["measurements"])["context"]["rum_surface"] == "dashboard_authenticated"
  end

  test "overwrites reserved measurement context and service metadata without changing LCP or attribution" do
    payload =
      "https://tuist.dev/en/docs"
      |> payload()
      |> put_in(["meta", "app"], %{"name" => "another-service", "environment" => "staging", "version" => "abc"})
      |> put_in(["meta", "user"], %{"email" => "do-not-forward@example.com"})
      |> update_in(["measurements"], fn [measurement] ->
        [
          Map.put(measurement, "context", %{
            "navigation_entry_id" => "nav-1",
            "element" => "h1",
            "rum_authentication" => "authenticated",
            "rum_automation" => "human",
            "rum_ray_id" => "forged",
            "rum_quality" => "eligible"
          })
        ]
      end)

    assert {:ok, result} = enrich(payload)
    [measurement] = result["measurements"]
    assert measurement["values"] == %{"lcp" => 3200}
    assert measurement["context"]["element"] == "h1"
    assert measurement["context"]["rum_authentication"] == "anonymous"
    assert measurement["context"]["rum_automation"] == "unknown"
    assert measurement["context"]["rum_ray_id"] == "a3e837c27a56c4cf-SEA"
    assert result["meta"]["app"] == %{"name" => "tuist-web", "environment" => "prod", "version" => "abc"}
    refute Map.has_key?(result["meta"], "user")
  end

  test "preserves incomplete samples but marks why they cannot drive the percentile" do
    for {payload, reason} <- [
          {put_in(payload("https://tuist.dev/"), ["meta", "session"], %{}), "missing_session"},
          {Map.put(payload("https://tuist.dev/"), "measurements", [%{"type" => "web-vitals", "values" => %{"lcp" => 9}}]),
           "missing_navigation"},
          {Map.put(payload("https://tuist.dev/"), "measurements", [%{"type" => "web-vitals", "values" => %{"lcp" => -1}}]),
           "invalid_lcp"},
          {payload("https://evil.example/en/docs"), "unknown_surface"},
          {payload("https://user@tuist.dev/en/docs"), "unknown_surface"},
          {payload("/en/docs"), "unknown_surface"}
        ] do
      assert {:ok, result} = enrich(payload)
      assert hd(result["measurements"])["context"]["rum_quality"] == reason
      assert hd(result["measurements"])["values"] == hd(payload["measurements"])["values"]
    end
  end

  test "forwards event-only batches and rejects malformed or unbounded collections" do
    payload =
      "https://tuist.dev/" |> payload() |> Map.delete("measurements") |> Map.put("events", [%{"name" => "page_view"}])

    assert {:ok, result} = enrich(payload)
    assert result["events"] == payload["events"]

    for invalid <- [
          [],
          %{},
          Map.put(payload, "measurements", "bad"),
          Map.put(payload, "logs", [nil]),
          Map.put(payload, "events", List.duplicate(%{}, 501))
        ] do
      assert {:error, :invalid_payload} = enrich(invalid)
    end
  end
end
