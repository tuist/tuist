defmodule Atlas.OrbitFixtures do
  @moduledoc false

  alias Atlas.Inference
  alias Atlas.LLMs.Runner
  alias Atlas.Orbit.Attachments
  alias Atlas.Users.User
  alias AtlasWeb.ConnCase

  def user_fixture(scopes \\ [], name \\ "Teammate") do
    unique = System.unique_integer([:positive])

    {:ok, user} =
      %User{}
      |> User.changeset(%{email: "threads-#{unique}@example.org", name: "#{name} #{unique}"})
      |> Atlas.Repo.insert()

    ConnCase.assign_role_or_scopes(user, nil, scopes)
    user
  end

  def bearer(%User{} = user) do
    Plug.Conn.put_req_header(
      Phoenix.ConnTest.build_conn(),
      "authorization",
      "Bearer #{ConnCase.oauth_access_token_fixture(user)}"
    )
  end

  def attachment_params(bytes \\ "Private attachment contents", attrs \\ %{}) do
    Map.merge(
      %{
        "filename" => "notes.txt",
        "content_type" => "text/plain",
        "data" => Base.encode64(bytes),
        "client_id" => Ecto.UUID.generate()
      },
      attrs
    )
  end

  def attachment_fixture(user, thread, bytes \\ "Private attachment contents", attrs \\ %{}) do
    {:ok, attachment} = Attachments.upload(user, thread, attachment_params(bytes, attrs))
    attachment
  end

  def png_fixture do
    Base.decode64!("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")
  end

  @doc "An enabled profile bound to the Orbit role, with its role token."
  def orbit_profile_fixture(attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    {:ok, provider} =
      Inference.create_provider(%{key: "threads-#{unique}", base_url: "https://provider.example/v1"})

    {:ok, profile} =
      attrs
      |> Enum.into(%{
        name: "threads-#{unique}",
        upstream_provider: provider.key,
        upstream_model: "example",
        atlas_orbit: true
      })
      |> Inference.create_profile()

    {:ok, {token, _value}} = Inference.ensure_atlas_token(profile, :orbit)
    {profile, token}
  end

  def completion(message, finish_reason \\ "stop") do
    %{
      "id" => "chatcmpl-test",
      "object" => "chat.completion",
      "created" => 0,
      "model" => "atlas-orbit",
      "choices" => [%{"index" => 0, "finish_reason" => finish_reason, "message" => message}],
      "usage" => %{"prompt_tokens" => 1, "completion_tokens" => 1, "total_tokens" => 2}
    }
  end

  def tool_call(name, arguments) do
    completion(
      %{
        "role" => "assistant",
        "content" => nil,
        "tool_calls" => [
          %{
            "id" => "call-#{name}",
            "type" => "function",
            "function" => %{"name" => name, "arguments" => JSON.encode!(arguments)}
          }
        ]
      },
      "tool_calls"
    )
  end

  @doc "Client options that route model requests to `plug` instead of the relay."
  def client_opts(plug) do
    :orbit
    |> Runner.profile_client_opts()
    |> Keyword.put(:llm_request_options, req_http_options: [plug: plug])
  end
end
