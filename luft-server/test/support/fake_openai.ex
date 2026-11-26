defmodule LuftServer.FakeOpenAI do
  @moduledoc """
  A stand-in for ChatGPT's Codex backend in tests, answering through
  `Req.Test` (`LuftServer.OpenAI`): the model catalog and buffered responses.
  `connect/2` saves a ChatGPT subscription the way a finished sign-in would.
  """
  import Plug.Conn

  alias LuftServer.AISubscriptions.Subscription
  alias LuftServer.Repo

  @doc "A ChatGPT access token shaped like OpenAI's, naming a ChatGPT account."
  def token do
    claims = %{
      "exp" => System.os_time(:second) + 3600,
      "https://api.openai.com/auth" => %{"chatgpt_account_id" => "account-1"}
    }

    "header." <> Base.url_encode64(Jason.encode!(claims), padding: false) <> ".signature"
  end

  @doc "Saves a connected ChatGPT subscription for the person `user_sub` names."
  def connect(user_sub, access_token \\ token()) do
    Repo.insert!(%Subscription{
      user_sub: to_string(user_sub),
      provider: :chatgpt,
      access_token: access_token,
      refresh_token: "refresh",
      client_id: "test-chatgpt-client",
      expires_at: DateTime.add(DateTime.utc_now(:second), 3600)
    })
  end

  @doc """
  Stubs the backend for the calling test. `models` are the slugs the catalog
  lists; `respond` receives the decoded responses request and returns the
  assistant's text, or a `Plug.Conn` to answer some other way.
  """
  def stub(opts \\ []) do
    models = Keyword.get(opts, :models, ["test-model"])
    respond = Keyword.get(opts, :respond, fn _request -> "hello" end)

    Req.Test.stub(LuftServer.OpenAI, fn conn ->
      case conn.request_path do
        "/backend-api/codex/models" ->
          Req.Test.json(conn, %{
            models:
              Enum.map(models, fn slug ->
                %{
                  slug: slug,
                  display_name: slug,
                  visibility: "list",
                  supported_reasoning_levels: [%{effort: "low"}]
                }
              end)
          })

        "/backend-api/codex/responses" ->
          {:ok, body, conn} = read_body(conn, length: 16_000_000)

          case respond.(Jason.decode!(body)) do
            %Plug.Conn{} = answered -> answered
            text when is_binary(text) -> send_resp(conn, 200, completed(text))
          end
      end
    end)
  end

  defp completed(text) do
    event = %{
      type: "response.completed",
      response: %{
        id: "response",
        model: "test-model",
        status: "completed",
        output: [
          %{type: "message", content: [%{type: "output_text", text: text}]}
        ],
        usage: %{input_tokens: 1, output_tokens: 1}
      }
    }

    "data: " <> Jason.encode!(event) <> "\n\n"
  end
end
