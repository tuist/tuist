defmodule AtlasWeb.Admin.InferenceProvidersLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.Inference
  alias Atlas.Inference.Provider

  test "creates a Jev provider with its native decision endpoint", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{role: :executive})
    {:ok, view, _html} = live(conn, "/admin/inference/providers")
    assert has_element?(view, "#new-inference-provider-modal")
    key = "typesafe-#{System.unique_integer([:positive])}"

    render_submit(view, "create_provider", %{
      "provider" => %{
        "key" => key,
        "base_url" => "https://api.typesafe.ai/v1",
        "decision_path" => "systemone",
        "api_key" => "test-secret",
        "timeout" => "60000"
      }
    })

    provider = Inference.get_provider_by_key(key)
    assert provider.decision_path == "systemone"
    assert Provider.api_key(provider) == "test-secret"
    assert has_element?(view, "#inference-providers-table", "systemone")
  end
end
