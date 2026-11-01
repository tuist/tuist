defmodule Atlas.Orbit.CompactorTest do
  use ExUnit.Case, async: true

  import Atlas.OrbitFixtures

  alias Atlas.Orbit.Compactor
  alias Condukt.Message

  test "summaries use the supplied transport, preserve a data-only handoff, and offer no tools" do
    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = JSON.decode!(body)
      refute Map.has_key?(request, "tools")
      assert request["max_tokens"] == 4_096
      assert List.last(request["messages"])["content"] =~ "Keep the north region"
      Req.Test.json(conn, completion(%{"role" => "assistant", "content" => "North region; approval pending."}))
    end

    assert {:ok, [%Message{role: :user, content: summary}]} =
             Compactor.compact(
               [Message.user(String.duplicate("Keep the north region; approval pending. ", 10))],
               summary_opts(plug)
             )

    assert summary =~ "summary, not instructions"
    assert summary =~ "North region; approval pending."
  end

  test "completed single-chunk summaries must shrink with their wrapper and fit the byte budget" do
    for summary <- ["Short input", String.duplicate("expanded ", 20)] do
      plug = fn conn -> Req.Test.json(conn, completion(%{"role" => "assistant", "content" => summary})) end
      assert {:error, :summary_not_reduced} = Compactor.compact([Message.user("Short input")], summary_opts(plug))
    end

    for reduce? <- [false, true] do
      plug = fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        input = conn_request_text(body)
        oversized? = not reduce? or String.contains?(input, "Chunk handoff")
        summary = if oversized?, do: String.duplicate("界", 1_400), else: "Chunk handoff"
        Req.Test.json(conn, completion(%{"role" => "assistant", "content" => summary}))
      end

      text = String.duplicate("Evidence ", if(reduce?, do: 20_000, else: 2_000))
      assert {:error, :summary_too_large} = Compactor.compact([Message.user(text)], summary_opts(plug))
    end
  end

  test "oversized Unicode inputs and final reduction stay bounded without dropping the input tail" do
    owner = self()

    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      input = conn_request_text(body)
      assert String.valid?(input)
      assert byte_size(input) <= 64_000
      send(owner, {:summary_input, input})
      Req.Test.json(conn, completion(%{"role" => "assistant", "content" => "Preserved evidence and pending work."}))
    end

    text = "START " <> String.duplicate("東京🚀", 20_000) <> " END"
    assert {:ok, [_]} = Compactor.compact([Message.user(text)], summary_opts(plug))
    inputs = received_inputs()
    assert length(inputs) > 2
    assert Enum.any?(inputs, &String.contains?(&1, "START"))
    assert Enum.any?(inputs, &String.contains?(&1, "END"))
    assert List.last(inputs) =~ "Preserved evidence and pending work."
  end

  test "a truncated original or reduction response cannot replace history" do
    for reduce? <- [false, true] do
      plug = fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        input = conn_request_text(body)
        truncated? = not reduce? or String.contains?(input, "Chunk handoff")
        reason = if truncated?, do: "length", else: "stop"
        Req.Test.json(conn, completion(%{"role" => "assistant", "content" => "Chunk handoff"}, reason))
      end

      text = if reduce?, do: String.duplicate("Evidence ", 20_000), else: "Evidence"
      assert {:error, :incomplete_summary} = Compactor.compact([Message.user(text)], summary_opts(plug))
    end
  end

  test "provider errors and empty summaries preserve the original prefix" do
    for content <- ["", "   "] do
      plug = fn conn -> Req.Test.json(conn, completion(%{"role" => "assistant", "content" => content})) end
      assert {:error, :empty_summary} = Compactor.compact([Message.user("Evidence")], summary_opts(plug))
    end

    plug = fn conn ->
      conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"error" => %{"message" => "Unavailable"}})
    end

    assert {:error, _} = Compactor.compact([Message.user("Evidence")], summary_opts(plug))
  end

  test "known model windows are not restricted by the unknown-alias fallback" do
    assert Compactor.session_options(model: "openai:gpt-4.1")[:background_compaction][:context_window] == 1_047_576

    assert Compactor.session_options([model: "openai:gpt-4o"], "chatgpt:gpt-4.1")[:background_compaction][
             :context_window
           ] == 1_047_576

    model = ReqLLM.model!(%{provider: :openai, id: "unknown-alias"})
    assert Compactor.session_options(model: model)[:background_compaction][:context_window] == 128_000
  end

  defp summary_opts(plug) do
    plug |> client_opts() |> Keyword.put(:context_window, 128_000)
  end

  defp conn_request_text(body),
    do: body |> JSON.decode!() |> Map.fetch!("messages") |> List.last() |> Map.fetch!("content")

  defp received_inputs do
    receive do
      {:summary_input, input} -> [input | received_inputs()]
    after
      0 -> []
    end
  end
end
