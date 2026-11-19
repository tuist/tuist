defmodule TuistWeb.AtlasEnvironmentsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.FeatureFlags
  alias Tuist.Sandboxes.AtlasIdentity
  alias TuistWeb.RateLimit

  setup :set_mimic_from_context

  test "provider routes require workload identity and preserve lifecycle fences through JSON requests" do
    account = account_fixture()
    environment = Ecto.UUID.generate()
    key = Ecto.UUID.generate()
    handle = account.name
    path = "/api/environment-providers/atlas/#{handle}/#{environment}"
    stub(RateLimit.Atlas, :hit, fn _ -> {:allow, 1} end)
    stub(FeatureFlags, :sandboxes_enabled?, fn _ -> true end)

    stub(AtlasIdentity, :verify, fn
      "valid", ^handle, ^environment -> {:ok, key}
      _, _, _ -> {:error, :unauthorized}
    end)

    for {method, suffix} <- [{:put, ""}, {:post, "/exec"}, {:post, "/pause"}, {:delete, ""}] do
      response = request(method, path <> suffix, %{"generation" => 7})
      assert json_response(response, 401) == %{"error" => "invalid_identity"}
      assert get_resp_header(response, "cache-control") == ["no-store"]
    end

    assert :post |> request(path <> "/pause", %{"generation" => 7}, "valid") |> json_response(200) == %{
             "state" => "paused"
           }

    assert :put |> request(path, %{"generation" => 7}, "valid") |> json_response(409) == %{
             "error" => "stale_generation"
           }

    assert :post |> request(path <> "/pause?generation=8", %{}, "valid") |> json_response(422) == %{
             "error" => "invalid_params"
           }

    assert :post |> request(path <> "/pause", %{"generation" => 8}, "forged") |> json_response(401) == %{
             "error" => "invalid_identity"
           }
  end

  defp request(method, path, body, token \\ "") do
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer " <> token)
    |> dispatch(@endpoint, method, path, JSON.encode!(body))
  end
end
