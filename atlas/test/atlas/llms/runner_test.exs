defmodule Atlas.LLMs.RunnerTest do
  use ExUnit.Case, async: true

  alias Atlas.LLMs.LocalTransport
  alias Atlas.LLMs.Runner

  describe "client_opts/1" do
    test "builds provider model specs from configured provider strings" do
      opts =
        Runner.client_opts(%{
          model: "openai:gpt-4.1",
          api_key: "api-key"
        })

      assert opts[:api_key] == "api-key"
      assert %{id: "gpt-4.1", provider: :openai} = opts[:model]
      assert opts[:retry] == false
    end

    test "raises a descriptive error for unsupported provider strings" do
      assert_raise ArgumentError, "unsupported LLM provider: unknown", fn ->
        Runner.client_opts(%{
          model: "unknown:some-model",
          api_key: "api-key"
        })
      end
    end

    test "includes a session timeout with buffer when ReqLLM receive timeout is configured" do
      opts =
        Runner.client_opts(%{
          model: "custom-model",
          api_key: "api-key",
          base_url: "https://llm.example",
          receive_timeout: :timer.minutes(5)
        })

      assert opts[:api_key] == "api-key"
      assert opts[:base_url] == "https://llm.example"
      assert opts[:model] == "custom-model"
      assert opts[:timeout] == :timer.minutes(5) + :timer.seconds(30)
    end

    test "omits timeout when ReqLLM receive timeout is not configured" do
      opts =
        Runner.client_opts(%{
          model: "custom-model",
          api_key: "api-key"
        })

      refute Keyword.has_key?(opts, :timeout)
    end

    test "local mode injects the LocalTransport plug and needs no model or api_key" do
      opts = Runner.client_opts(%{mode: :local})

      # The model id is a sentinel — LocalTransport rewrites it to the
      # default profile's name before the request reaches the controller.
      # Provider is fixed to :openai because Atlas.Inference speaks the
      # OpenAI-compatible surface.
      assert %{id: "atlas-default", provider: :openai} = opts[:model]
      assert opts[:api_key] == "local"
      assert opts[:retry] == false
      # The plug must live under `llm_request_options`: Condukt only threads
      # `req_http_options` through to ReqLLM when it arrives nested there. A
      # top-level `req_http_options` is silently dropped, which sends every
      # local-mode agent call to the sentinel host instead of the plug.
      assert opts[:llm_request_options] == [req_http_options: [plug: {LocalTransport, []}]]
      refute Keyword.has_key?(opts, :req_http_options)
      # Base URL is a sentinel that Req uses to construct a valid URL before
      # the plug intercepts. It should never leave the process.
      assert opts[:base_url] == "http://atlas-local"
    end
  end

  describe "local-mode plug threading through Condukt" do
    # Guards against the regression that caused every classifier call in
    # production to fail with `:nxdomain`: Condukt 1.7.0 silently dropped
    # `:llm_request_options`, so the LocalTransport plug never attached
    # and every ReqLLM call escaped to the `http://atlas-local` sentinel
    # host. Condukt 1.13+ wires `:llm_request_options` into the base opts
    # of `ReqLLM.generate_text`, which carries `:req_http_options` into
    # `Req.new/1`, which honors the `:plug` adapter. If a future Condukt
    # downgrade or refactor loses that forwarding, this test fires before
    # the Slack #support ping degrades silently.
    test "the ReqLLM request flows through the Plug carried in llm_request_options" do
      test_pid = self()

      defmodule ProbePlug do
        @behaviour Plug
        import Plug.Conn

        @impl true
        def init(opts), do: opts

        @impl true
        def call(conn, opts) do
          send(opts[:test_pid], {:probe_plug_called, conn.request_path})

          body =
            JSON.encode!(%{
              "id" => "chatcmpl-test",
              "object" => "chat.completion",
              "created" => 0,
              "model" => "probe-model",
              "choices" => [
                %{
                  "index" => 0,
                  "finish_reason" => "stop",
                  "message" => %{"role" => "assistant", "content" => "ok"}
                }
              ],
              "usage" => %{"prompt_tokens" => 1, "completion_tokens" => 1, "total_tokens" => 2}
            })

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, body)
        end
      end

      defmodule ProbeAgent do
        use Condukt
        @impl true
        def system_prompt, do: "You are a probe."
      end

      opts = [
        model: ReqLLM.model!(%{id: "probe-model", provider: :openai}),
        api_key: "test",
        base_url: "http://atlas-local",
        llm_request_options: [req_http_options: [plug: {ProbePlug, test_pid: test_pid}]]
      ]

      assert {:ok, _response} = Condukt.run(ProbeAgent, "ping", opts)
      assert_receive {:probe_plug_called, "/chat/completions"}, 2_000
    end
  end
end
