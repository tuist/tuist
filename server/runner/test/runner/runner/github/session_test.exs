defmodule Runner.Runner.GitHub.SessionTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Runner.Runner.GitHub.{Auth, Session}

  describe "create_session/3" do
    test "creates session with Broker API" do
      Mimic.stub(Auth, :ensure_valid_token, fn creds -> {:ok, creds} end)

      Mimic.stub(Req, :post, fn url, opts ->
        assert String.contains?(url, "/sessions")
        assert opts[:headers] |> Enum.any?(fn {k, _} -> k == "Authorization" end)

        body = Jason.decode!(opts[:body])
        assert body["sessionId"]
        assert body["agent"]["id"] == 123

        {:ok,
         %Req.Response{
           status: 200,
           body: %{"sessionId" => body["sessionId"]}
         }}
      end)

      credentials = %{
        access_token: "test-token",
        token_expires_at: DateTime.utc_now() |> DateTime.add(3600, :second)
      }

      runner_info = %{runner_id: 123, runner_name: "test-runner"}

      assert {:ok, session} = Session.create_session("https://actions.githubusercontent.com/abc", credentials, runner_info)
      assert session.session_id
      assert session.owner_name
    end

    test "returns error on session rejection" do
      Mimic.stub(Auth, :ensure_valid_token, fn creds -> {:ok, creds} end)

      Mimic.stub(Req, :post, fn _url, _opts ->
        {:ok, %Req.Response{status: 400, body: %{"message" => "Runner version too old"}}}
      end)

      credentials = %{access_token: "test-token", token_expires_at: DateTime.utc_now()}
      runner_info = %{runner_id: 123, runner_name: "test-runner"}

      assert {:error, {:session_rejected, _}} =
               Session.create_session("https://actions.githubusercontent.com/abc", credentials, runner_info)
    end
  end

  describe "delete_session/3" do
    test "deletes session successfully" do
      Mimic.stub(Auth, :ensure_valid_token, fn creds -> {:ok, creds} end)

      Mimic.stub(Req, :delete, fn url, _opts ->
        assert String.contains?(url, "/sessions/test-session-id")
        {:ok, %Req.Response{status: 204}}
      end)

      credentials = %{access_token: "test-token", token_expires_at: DateTime.utc_now()}

      assert :ok = Session.delete_session("https://actions.githubusercontent.com/abc", credentials, "test-session-id")
    end

    test "returns ok when session not found (already deleted)" do
      Mimic.stub(Auth, :ensure_valid_token, fn creds -> {:ok, creds} end)

      Mimic.stub(Req, :delete, fn _url, _opts ->
        {:ok, %Req.Response{status: 404}}
      end)

      credentials = %{access_token: "test-token", token_expires_at: DateTime.utc_now()}

      assert :ok = Session.delete_session("https://actions.githubusercontent.com/abc", credentials, "test-session-id")
    end
  end
end
