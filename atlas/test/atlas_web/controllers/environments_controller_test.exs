defmodule AtlasWeb.EnvironmentsControllerTest do
  use AtlasWeb.ConnCase, async: true

  import Atlas.EnvironmentFixtures
  import Atlas.OrbitFixtures
  import Atlas.PushFixtures, only: [native_access_token: 1]

  alias Atlas.Environments
  alias Atlas.Repo

  setup do
    c = environment_fixture()
    Map.put(c, :api, build_conn() |> put_req_header("authorization", "Bearer #{c.token}"))
  end

  test "requires bearer auth and native OAuth for mutations", c do
    assert build_conn() |> get("/api/me/environments") |> json_response(401)

    assert bearer(c.user) |> put(path(c), registration(c.project_id)) |> json_response(403) == %{
             "error" => "native_client_required"
           }

    assert get(c.api, "/api/me/environments") |> json_response(200) |> Map.keys() |> Enum.sort() == [
             "environments",
             "owner_id"
           ]
  end

  test "registration, deletion and result success envelopes are stable", c do
    response = put(c.api, path(c), registration(c.project_id))
    assert %{"environment" => environment} = json_response(response, 200)
    assert Map.keys(environment) |> Enum.sort() == ~w(display enabled id name online projects terminal)
    assert get_resp_header(response, "cache-control") == ["no-store"]
    command = command_fixture(c)
    claimed = claim_fixture(c, command)
    result_path = "#{path(c)}/commands/#{command.id}/result"
    body = %{"claim_token" => claimed.claim_token, "success" => true, "output" => "local result"}
    assert post(c.api, result_path, body) |> json_response(200) == %{"received" => true}
    assert post(c.api, result_path, body) |> json_response(200) == %{"received" => true}
    assert delete(c.api, path(c)) |> json_response(200) == %{"disabled" => true}
    assert delete(c.api, path(c)) |> json_response(200) == %{"disabled" => true}
  end

  test "authoritative polling and claims obey client isolation and exact JSON shapes", c do
    command = command_fixture(c)

    assert %{"commands" => [%{"id" => id, "arguments" => %{"project_id" => project}}]} =
             get(c.api, "#{path(c)}/commands") |> json_response(200)

    assert id == command.id and project == c.project_id
    {_client, other_token} = native_access_token(c.user)
    other = build_conn() |> put_req_header("authorization", "Bearer #{other_token}")
    assert get(other, "#{path(c)}/commands") |> json_response(404) == %{"error" => "not_found"}
    claim_path = "#{path(c)}/commands/#{command.id}/claim"

    assert post(c.api, claim_path, %{"digest" => command.digest, "approved" => true, "owner_id" => c.user.id})
           |> json_response(422) == %{"error" => "invalid_params"}

    assert %{"command" => %{"claim_token" => token}} =
             post(c.api, claim_path, %{"digest" => command.digest}) |> json_response(200)

    assert {:ok, _} = Ecto.UUID.cast(token)

    assert post(c.api, claim_path, %{"digest" => command.digest}) |> json_response(409) == %{
             "error" => "command_claimed_or_settled"
           }
  end

  test "Orbit selection and metadata are additive, exact and owner-private", c do
    Repo.delete!(c.run)
    route = "/api/native/orbit/threads/#{c.thread.id}/environment"

    assert %{"thread" => %{"environment_id" => nil, "environment_name" => nil, "project_id" => nil}} =
             patch(c.api, route, %{"environment_id" => nil, "project_id" => nil}) |> json_response(200)

    assert patch(c.api, route, %{"environment_id" => nil, "project_id" => nil, "owner_id" => c.user.id})
           |> json_response(422) == %{"error" => "invalid_params"}

    assert %{"thread" => %{"environment_name" => "Personal Mac"}} =
             patch(c.api, route, %{"environment_id" => c.environment.id, "project_id" => c.project_id})
             |> json_response(200)

    assert %{"assistant" => %{"environments" => true}} = get(c.api, "/api/native/orbit/threads") |> json_response(200)
    assert bearer(user_fixture()) |> patch(route, %{"environment_id" => nil, "project_id" => nil}) |> json_response(404)
    assert {:ok, _} = Environments.disable(c.user, c.client_id, c.environment.id)

    assert patch(c.api, route, %{"environment_id" => c.environment.id, "project_id" => c.project_id})
           |> json_response(409) == %{"error" => "environment_disabled"}
  end

  defp path(c), do: "/api/me/environments/#{c.environment.id}"
end
