defmodule Condukt.PlugTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Condukt.Test.LLMProvider
  alias ReqLLM.Message
  alias ReqLLM.ToolCall

  @opts Plug.Parsers.init(parsers: [:json], json_decoder: JSON)

  defmodule ReviewAgent do
    use Condukt

    operation(:review_pr,
      input: %{
        type: "object",
        properties: %{
          repo: %{type: "string"},
          pr_number: %{type: "integer"}
        },
        required: ["repo", "pr_number"]
      },
      output: %{
        type: "object",
        properties: %{
          verdict: %{type: "string"},
          summary: %{type: "string"}
        },
        required: ["verdict", "summary"]
      },
      instructions: "Review the pull request."
    )
  end

  defmodule AssistantAgent do
    use Condukt

    @impl true
    def system_prompt, do: "You are an assistant exposed over HTTP."
  end

  defmodule Router do
    use Plug.Router

    plug(Plug.Parsers, parsers: [:json], json_decoder: JSON)
    plug(:match)
    plug(:dispatch)

    post("/assistant",
      to: Condukt.Plug,
      init_opts: [
        agent: AssistantAgent,
        run_opts: &__MODULE__.run_opts/1
      ]
    )

    post("/assistant-default",
      to: Condukt.Plug,
      init_opts: [
        agent: AssistantAgent,
        prompt: "Use the route default prompt.",
        run_opts: &__MODULE__.run_opts/1
      ]
    )

    post("/review",
      to: Condukt.Plug,
      init_opts: [
        agent: ReviewAgent,
        operation: :review_pr
      ]
    )

    post("/review-with-opts",
      to: Condukt.Plug,
      init_opts: [
        agent: ReviewAgent,
        operation: :review_pr,
        run_opts: &__MODULE__.run_opts/1
      ]
    )

    post("/custom-input",
      to: Condukt.Plug,
      init_opts: [
        agent: ReviewAgent,
        operation: :review_pr,
        input: &__MODULE__.custom_input/1,
        run_opts: &__MODULE__.run_opts/1
      ]
    )

    def run_opts(_conn), do: [model: Process.get(:condukt_plug_model), load_project_instructions: false]

    def custom_input(conn), do: %{"repo" => conn.params["repo"], "pr_number" => 1}

    match _ do
      send_resp(conn, 404, "not found")
    end
  end

  describe "operation routes" do
    test "runs an operation and returns its structured result as JSON" do
      model = model_for(%{"verdict" => "approve", "summary" => "Looks good."})
      Process.put(:condukt_plug_model, model)

      conn =
        conn(:post, "/review-with-opts", JSON.encode!(%{repo: "tuist/condukt", pr_number: 1}))
        |> put_req_header("content-type", "application/json")
        |> Router.call([])

      assert conn.status == 200

      assert JSON.decode!(conn.resp_body) == %{
               "ok" => true,
               "result" => %{"verdict" => "approve", "summary" => "Looks good."}
             }
    after
      Process.delete(:condukt_plug_model)
    end

    test "validates parsed request body params against the operation input schema" do
      conn =
        conn(:post, "/review", JSON.encode!(%{repo: "tuist/condukt"}))
        |> put_req_header("content-type", "application/json")
        |> Router.call([])

      assert conn.status == 422
      assert %{"ok" => false, "error" => %{"code" => "invalid_input"}} = JSON.decode!(conn.resp_body)
    end

    test "can derive input from the conn" do
      model = model_for(%{"verdict" => "comment", "summary" => "Checked path params."})
      Process.put(:condukt_plug_model, model)

      conn =
        conn(:post, "/custom-input?repo=tuist/condukt", "")
        |> Router.call([])

      assert conn.status == 200
      assert %{"ok" => true, "result" => %{"verdict" => "comment"}} = JSON.decode!(conn.resp_body)
    after
      Process.delete(:condukt_plug_model)
    end
  end

  describe "agent routes" do
    test "runs a module-defined one-shot agent with the request prompt" do
      {model, model_id} = LLMProvider.model(LLMProvider.text_response("agent answer"))
      Process.put(:condukt_plug_model, model)

      conn =
        conn(:post, "/assistant", JSON.encode!(%{prompt: "Summarize this ticket."}))
        |> put_req_header("content-type", "application/json")
        |> Router.call([])

      assert conn.status == 200
      assert JSON.decode!(conn.resp_body) == %{"ok" => true, "result" => "agent answer"}

      assert_receive {LLMProvider, :request, ^model_id, context, _opts}
      assert inspect(context) =~ "Summarize this ticket."
    after
      Process.delete(:condukt_plug_model)
    end

    test "runs a module-defined one-shot agent with a raw prompt body" do
      {model, model_id} = LLMProvider.model(LLMProvider.text_response("raw answer"))
      Process.put(:condukt_plug_model, model)

      conn =
        conn(:post, "/assistant", "Summarize this raw body.")
        |> Router.call([])

      assert conn.status == 200
      assert JSON.decode!(conn.resp_body) == %{"ok" => true, "result" => "raw answer"}

      assert_receive {LLMProvider, :request, ^model_id, context, _opts}
      assert inspect(context) =~ "Summarize this raw body."
    after
      Process.delete(:condukt_plug_model)
    end

    test "runs a module-defined one-shot agent with a JSON string body" do
      {model, model_id} = LLMProvider.model(LLMProvider.text_response("string answer"))

      conn =
        conn(:post, "/assistant", JSON.encode!("Summarize this JSON string."))
        |> put_req_header("content-type", "application/json")
        |> Condukt.Plug.call(agent: AssistantAgent, run_opts: [model: model, load_project_instructions: false])

      assert conn.status == 200
      assert JSON.decode!(conn.resp_body) == %{"ok" => true, "result" => "string answer"}

      assert_receive {LLMProvider, :request, ^model_id, context, _opts}
      assert inspect(context) =~ "Summarize this JSON string."
    end

    test "uses the route prompt when the request omits one" do
      {model, model_id} = LLMProvider.model(LLMProvider.text_response("default answer"))
      Process.put(:condukt_plug_model, model)

      conn =
        conn(:post, "/assistant-default", JSON.encode!(%{}))
        |> put_req_header("content-type", "application/json")
        |> Router.call([])

      assert conn.status == 200
      assert JSON.decode!(conn.resp_body) == %{"ok" => true, "result" => "default answer"}

      assert_receive {LLMProvider, :request, ^model_id, context, _opts}
      assert inspect(context) =~ "Use the route default prompt."
    after
      Process.delete(:condukt_plug_model)
    end

    test "rejects non-string prompts" do
      conn =
        conn(:post, "/assistant", JSON.encode!(%{prompt: %{text: "nope"}}))
        |> put_req_header("content-type", "application/json")
        |> Router.call([])

      assert conn.status == 400
      assert %{"ok" => false, "error" => %{"code" => "invalid_prompt"}} = JSON.decode!(conn.resp_body)
    end

    test "returns 400 for invalid JSON prompt bodies when content type is JSON" do
      conn =
        conn(:post, "/assistant", "{not json")
        |> put_req_header("content-type", "application/json")
        |> Condukt.Plug.call(agent: AssistantAgent)

      assert conn.status == 400
      assert %{"ok" => false, "error" => %{"code" => "invalid_json"}} = JSON.decode!(conn.resp_body)
    end
  end

  describe "direct plug usage" do
    test "reads and decodes the JSON body when Plug.Parsers has not run" do
      model = model_for(%{"verdict" => "approve", "summary" => "Direct plug."})

      conn =
        conn(:post, "/review", JSON.encode!(%{repo: "tuist/condukt", pr_number: 1}))
        |> Condukt.Plug.call(agent: ReviewAgent, operation: :review_pr, run_opts: [model: model])

      assert conn.status == 200
      assert %{"ok" => true, "result" => %{"summary" => "Direct plug."}} = JSON.decode!(conn.resp_body)
    end

    test "returns 400 for invalid JSON" do
      conn =
        conn(:post, "/review", "{")
        |> Condukt.Plug.call(agent: ReviewAgent, operation: :review_pr)

      assert conn.status == 400
      assert %{"ok" => false, "error" => %{"code" => "invalid_json"}} = JSON.decode!(conn.resp_body)
    end

    test "returns 404 for unknown operations" do
      conn =
        conn(:post, "/missing", JSON.encode!(%{}))
        |> Plug.Parsers.call(@opts)
        |> Condukt.Plug.call(agent: ReviewAgent, operation: :missing)

      assert conn.status == 404
      assert %{"ok" => false, "error" => %{"code" => "unknown_operation"}} = JSON.decode!(conn.resp_body)
    end
  end

  defp model_for(output) do
    tool_call = ToolCall.new("call_1", "submit_result", JSON.encode!(output))

    {model, _model_id} =
      LLMProvider.model([
        LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [tool_call]}, :tool_calls),
        LLMProvider.text_response("Done.")
      ])

    model
  end
end
