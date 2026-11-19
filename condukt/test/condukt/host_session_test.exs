defmodule Condukt.HostSessionTest do
  use ExUnit.Case, async: true

  alias Condukt.HostSession
  alias Condukt.Message

  defp tool_call(id \\ "call-1"), do: Message.assistant([{:tool_call, id, "read_page", %{}}])
  defp output(id, content, error? \\ false), do: %{tool_call_id: id, content: content, error?: error?}

  describe "starting" do
    test "the system prompt rides on the request rather than in history" do
      {:ok, request, _session} =
        HostSession.new(system_prompt: "Be useful") |> HostSession.submit("hello")

      assert request.system_prompt == "Be useful"
      assert [%Message{role: :user}] = request.messages
    end

    test "a blank system prompt is treated as none" do
      assert HostSession.new(system_prompt: "   ").system_prompt == nil
      assert HostSession.new().system_prompt == nil
    end

    test "tools are sent on every request, not only the first" do
      tools = [%{name: "read_page", description: "Read", parameters: %{}}]
      {:ok, first, session} = HostSession.new(tools: tools) |> HostSession.submit("hello")
      {:ok, {:run_tools, _message, _calls}, session} = HostSession.receive_completion(session, tool_call())
      {:ok, second, _session} = HostSession.receive_tool_outputs(session, [output("call-1", "done")])

      assert first.tools == tools
      assert second.tools == tools
    end
  end

  describe "a turn" do
    test "runs completion, tools, then completion again" do
      {:ok, _request, session} = HostSession.new() |> HostSession.submit("What is here?")

      assert {:ok, {:run_tools, _message, [{"call-1", "read_page", %{}}]}, session} =
               HostSession.receive_completion(session, tool_call())

      assert {:ok, request, session} =
               HostSession.receive_tool_outputs(session, [output("call-1", "Condukt is portable")])

      assert [%{role: :user}, %{role: :assistant}, %{role: :tool_result}] = request.messages

      assert {:ok, {:complete, message}, session} =
               HostSession.receive_completion(session, Message.assistant("It runs in your browser."))

      assert Message.text(message) == "It runs in your browser."
      refute HostSession.in_progress?(session)
    end

    test "a reply with no tool calls ends the turn" do
      {:ok, _request, session} = HostSession.new() |> HostSession.submit("hello")

      assert {:ok, {:complete, _message}, session} =
               HostSession.receive_completion(session, Message.assistant("hi"))

      refute HostSession.in_progress?(session)
    end

    test "a tool error is marked in the transcript" do
      {:ok, _request, session} = HostSession.new() |> HostSession.submit("hello")
      {:ok, {:run_tools, _message, _calls}, session} = HostSession.receive_completion(session, tool_call())

      {:ok, request, _session} =
        HostSession.receive_tool_outputs(session, [output("call-1", "no such page", true)])

      assert List.last(request.messages).content =~ "Tool error: no such page"
    end

    # Ordering the transcript by what was asked, not by what happened to finish
    # first, keeps it readable and matches what the model expects back.
    test "results are recorded in the order the calls were requested" do
      {:ok, _request, session} = HostSession.new() |> HostSession.submit("hello")

      two_calls =
        Message.assistant([
          {:tool_call, "a", "read_page", %{}},
          {:tool_call, "b", "read_page", %{}}
        ])

      {:ok, {:run_tools, _message, _calls}, session} = HostSession.receive_completion(session, two_calls)

      {:ok, request, _session} =
        HostSession.receive_tool_outputs(session, [output("b", "second"), output("a", "first")])

      assert Enum.map(tl(tl(request.messages)), & &1.content) == ["first", "second"]
    end
  end

  describe "refusing what would corrupt the conversation" do
    test "a second prompt mid-turn" do
      {:ok, _request, session} = HostSession.new() |> HostSession.submit("first")

      assert {:error, :turn_in_progress} = HostSession.submit(session, "second")
    end

    test "a completion nobody asked for" do
      assert {:error, :not_waiting_for_completion} =
               HostSession.receive_completion(HostSession.new(), Message.assistant("unprompted"))
    end

    test "a reply that is not from the assistant" do
      {:ok, _request, session} = HostSession.new() |> HostSession.submit("hello")

      assert {:error, :invalid_response_role} = HostSession.receive_completion(session, Message.user("nope"))
    end

    test "tool results nobody asked for" do
      {:ok, _request, session} = HostSession.new() |> HostSession.submit("hello")

      assert {:error, :not_waiting_for_tools} =
               HostSession.receive_tool_outputs(session, [output("call-1", "x")])
    end

    # Recoverable on purpose: the host can answer correctly rather than being
    # left with a session it can no longer advance.
    test "mismatched results leave the session able to try again" do
      {:ok, _request, session} = HostSession.new() |> HostSession.submit("hello")
      {:ok, {:run_tools, _message, _calls}, session} = HostSession.receive_completion(session, tool_call())

      assert {:error, :invalid_tool_results} =
               HostSession.receive_tool_outputs(session, [output("wrong-id", "x")])

      assert {:ok, _request, _session} =
               HostSession.receive_tool_outputs(session, [output("call-1", "recovered")])
    end

    test "the wrong number of results" do
      {:ok, _request, session} = HostSession.new() |> HostSession.submit("hello")
      {:ok, {:run_tools, _message, _calls}, session} = HostSession.receive_completion(session, tool_call())

      assert {:error, :invalid_tool_results} =
               HostSession.receive_tool_outputs(session, [output("call-1", "x"), output("call-1", "again")])
    end

    # A model that keeps asking for tools would otherwise loop forever in a
    # host with nobody watching it.
    test "an endless tool loop stops at the iteration limit" do
      {:ok, _request, session} = HostSession.new() |> HostSession.submit("loop")

      result =
        Enum.reduce_while(1..20, session, fn iteration, session ->
          {:ok, {:run_tools, _message, _calls}, session} =
            HostSession.receive_completion(session, tool_call("call-#{iteration}"))

          case HostSession.receive_tool_outputs(session, [output("call-#{iteration}", "again")]) do
            {:ok, _request, session} -> {:cont, session}
            {:error, reason} -> {:halt, reason}
          end
        end)

      assert result == :iteration_limit
    end
  end

  describe "history" do
    test "accumulates the turn in order" do
      {:ok, _request, session} = HostSession.new() |> HostSession.submit("hello")
      {:ok, {:complete, _message}, session} = HostSession.receive_completion(session, Message.assistant("hi"))

      assert [%{role: :user, content: "hello"}, %{role: :assistant}] = HostSession.history(session)
    end

    test "starts empty" do
      assert HostSession.history(HostSession.new(system_prompt: "Be useful")) == []
    end
  end
end
