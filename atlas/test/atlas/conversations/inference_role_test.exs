defmodule Atlas.Conversations.InferenceRoleTest do
  # These tests assign and reassign the singleton conversations role.
  # credo:disable-for-next-line Credo.Check.Warning.AsyncTests
  use AtlasWeb.ConnCase, async: false

  import Atlas.ConversationsFixtures
  import Phoenix.LiveViewTest

  alias Atlas.Inference
  alias Atlas.Inference.Usage
  alias Atlas.LLMs.LocalTransport
  alias Atlas.Repo

  test "the conversations role is a singleton with its own token and no output cap" do
    {first, token} = conversations_profile_fixture()
    assert token.atlas_role == "conversations"
    assert {:ok, binding, _token} = Inference.fetch_atlas_role(:conversations)
    assert binding.id == first.id

    {second, _token} = conversations_profile_fixture()
    refute Repo.reload!(first).atlas_conversations
    assert {:ok, %{id: id}, _} = Inference.fetch_atlas_role(:conversations)
    assert id == second.id

    body = %{"max_tokens" => 4_096}
    assert Inference.cap_atlas_inference_output(token, body) == body
  end

  test "an explicit role never falls back to another role's profile", %{conn: conn} do
    unique = System.unique_integer([:positive])
    {:ok, provider} = Inference.create_provider(%{key: "fallback-#{unique}", base_url: "https://provider.example/v1"})

    {:ok, inference_profile} =
      Inference.create_profile(%{
        name: "general-#{unique}",
        upstream_provider: provider.key,
        upstream_model: "example",
        atlas_inference: true
      })

    {:ok, _} = Inference.ensure_atlas_token(inference_profile, :inference)
    refute Inference.atlas_role_configured?(:conversations)

    response =
      conn
      |> Map.put(:path_info, ["chat", "completions"])
      |> Map.put(:body_params, %{"model" => "x", "messages" => []})
      |> LocalTransport.call(role: :conversations)

    assert response.status == 503
    assert response.resp_body =~ "atlas_conversations"
  end

  test "requests for the conversations role relay through its own profile and record usage", %{conn: conn} do
    {profile, token} = conversations_profile_fixture()
    test_pid = self()

    Inference.put_process_config(
      providers: %{profile.upstream_provider => %{base_url: "https://provider.example/v1", api_key: "secret"}},
      request: fn options ->
        send(test_pid, {:upstream, options[:json]["model"]})
        {:ok, %Req.Response{status: 200, body: completion(%{"role" => "assistant", "content" => "hi"})}}
      end
    )

    on_exit(&Inference.delete_process_config/0)

    response =
      conn
      |> Map.put(:path_info, ["chat", "completions"])
      |> Map.put(:body_params, %{
        "model" => "atlas-conversations",
        "messages" => [%{"role" => "user", "content" => "hi"}]
      })
      |> LocalTransport.call(role: :conversations)

    assert response.status == 200
    assert_receive {:upstream, "example"}
    assert Repo.get_by!(Usage, token_id: token.id).model_binding_id == profile.id
  end

  test "administrators assign the conversations role from the profile page", %{conn: conn} do
    unique = System.unique_integer([:positive])
    {:ok, provider} = Inference.create_provider(%{key: "admin-#{unique}", base_url: "https://provider.example/v1"})

    {:ok, profile} =
      Inference.create_profile(%{name: "admin-#{unique}", upstream_provider: provider.key, upstream_model: "example"})

    {conn, _user} = log_in_user(conn, %{role: :executive})
    {:ok, view, _html} = live(conn, "/admin/inference/profiles/#{profile.id}")

    render_click(view, "set_atlas_role", %{"role" => "conversations", "enabled" => "true"})

    assert Repo.reload!(profile).atlas_conversations
    assert Inference.atlas_role_configured?(:conversations)
    assert render(view) =~ "Conversations"
  end
end
