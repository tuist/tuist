defmodule Atlas.LLMs.PersonalTransportTest do
  use Atlas.DataCase, async: true
  use Mimic

  import Atlas.OrbitFixtures

  alias Atlas.LLMs.Connection
  alias Atlas.LLMs.Connections
  alias Atlas.LLMs.PersonalTransport
  alias Atlas.LLMs.Runner
  alias Atlas.Orbit
  alias Atlas.Orbit.Run

  test "only the acting person's accounts are tried, before any system fallback" do
    actor = user_fixture()
    other = user_fixture()
    connect(actor, "actor")
    connect(other, "other")
    assert Runner.orbit_configured?(actor)
    refute Runner.orbit_configured?(user_fixture())

    expect(Req, :post, fn opts ->
      assert {"authorization", "Bearer " <> token("actor")} in opts[:headers]
      {:ok, %{status: 429, body: "private upstream error"}}
    end)

    expect(Req, :post, fn opts ->
      assert {"authorization", "Bearer " <> claude_token("actor")} in opts[:headers]
      {:ok, %{status: 200, body: claude_reply()}}
    end)

    conn = request(actor)
    assert conn.status == 200
    assert conn.resp_body =~ "Personal reply"
    refute conn.resp_body =~ "private upstream error"
  end

  test "disconnect takes effect on the next model turn and saved credentials never enter session options" do
    actor = user_fixture()
    {:ok, _} = Connections.connect_claude(actor, claude_token("actor"))
    opts = Runner.orbit_client_opts(actor)
    refute inspect(opts) =~ claude_token("actor")

    expect(Req, :post, fn _opts -> {:ok, %{status: 200, body: claude_reply()}} end)
    assert request(actor).status == 200
    assert {:ok, _} = Connections.disconnect(actor, "claude")
    assert request(actor).status == 503
  end

  test "cancellation during a rejected personal request prevents the next provider dispatch" do
    actor = user_fixture()
    connect(actor, "actor")
    {:ok, thread, _} = Orbit.ensure_private(actor)
    run = Repo.insert!(%Run{thread_id: thread.id, acting_user_id: actor.id, trigger_seq: 0, status: "running"})

    expect(Req, :post, fn _opts ->
      Repo.update!(Ecto.Changeset.change(run, cancel_requested_at: DateTime.utc_now()))
      {:ok, %{status: 401, body: "private rejection"}}
    end)

    conn =
      Plug.Test.conn(
        :post,
        "/chat/completions",
        JSON.encode!(%{"messages" => [%{"role" => "user", "content" => "Hi"}]})
      )
      |> Plug.Conn.put_private(:orbit_model_fence, {run.id, run.resume_count})
      |> PersonalTransport.call(user_id: actor.id)

    assert conn.status == 409
  end

  test "a failed personal provider retains a sanitized actionable status when no fallback is configured" do
    actor = user_fixture()
    {:ok, _} = Connections.connect_claude(actor, claude_token("actor"))

    for status <- [400, 401, 402, 403, 429, 502] do
      expect(Req, :post, fn _opts -> {:ok, %{status: status, body: "private provider payload"}} end)
      conn = request(actor)
      assert conn.status == status
      refute conn.resp_body =~ "private provider payload"
    end
  end

  defp connect(user, suffix) do
    Repo.insert!(%Connection{
      user_id: user.id,
      provider: "chatgpt",
      access_token: token(suffix),
      refresh_token: "test-refresh-#{suffix}",
      expires_at: DateTime.add(DateTime.utc_now(:second), 3600)
    })

    {:ok, _} = Connections.connect_claude(user, claude_token(suffix))
  end

  defp request(user) do
    Plug.Test.conn(:post, "/chat/completions", JSON.encode!(%{"messages" => [%{"role" => "user", "content" => "Hi"}]}))
    |> PersonalTransport.call(user_id: user.id)
  end

  defp claude_reply do
    %{"id" => "msg-1", "model" => "claude-sonnet-4-6", "content" => [%{"type" => "text", "text" => "Personal reply"}]}
  end

  defp claude_token(suffix), do: "sk-ant-oat01-" <> String.duplicate(suffix, 12)

  defp token(account) do
    claims = %{"https://api.openai.com/auth" => %{"chatgpt_account_id" => account}}
    "header." <> Base.url_encode64(JSON.encode!(claims), padding: false) <> ".signature"
  end
end
