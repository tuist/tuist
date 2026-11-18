defmodule Condukt.MessageTest do
  use ExUnit.Case, async: true

  alias Condukt.Message

  test "creates user message" do
    msg = Message.user("Hello")
    assert msg.role == :user
    assert msg.content == "Hello"
    assert msg.images == []
  end

  test "creates user message with images" do
    images = [%{type: :base64, media_type: "image/png", data: "abc123"}]
    msg = Message.user("What's this?", images)
    assert msg.role == :user
    assert msg.images == images
  end

  test "creates assistant message with text" do
    msg = Message.assistant("Hello back!")
    assert msg.role == :assistant
    assert msg.content == "Hello back!"
  end

  test "creates assistant message with blocks" do
    blocks = [
      {:text, "Let me help"},
      {:tool_call, "123", "read", %{"path" => "test.txt"}}
    ]

    msg = Message.assistant(blocks)
    assert msg.role == :assistant
    assert msg.content == blocks
  end

  test "creates tool result message" do
    msg = Message.tool_result("123", "file contents")
    assert msg.role == :tool_result
    assert msg.tool_call_id == "123"
    assert msg.content == "file contents"
  end

  test "extracts text from string content" do
    msg = Message.assistant("Hello")
    assert Message.text(msg) == "Hello"
  end

  test "extracts text from blocks" do
    blocks = [
      {:thinking, "hmm..."},
      {:text, "Hello "},
      {:text, "world"}
    ]

    msg = Message.assistant(blocks)
    assert Message.text(msg) == "Hello world"
  end

  test "detects tool calls" do
    no_tools = Message.assistant("Just text")
    assert Message.has_tool_calls?(no_tools) == false

    with_tools =
      Message.assistant([
        {:text, "Let me check"},
        {:tool_call, "123", "read", %{"path" => "file.txt"}}
      ])

    assert Message.has_tool_calls?(with_tools) == true
  end

  test "extracts tool calls" do
    msg =
      Message.assistant([
        {:text, "Checking files"},
        {:tool_call, "1", "read", %{"path" => "a.txt"}},
        {:tool_call, "2", "read", %{"path" => "b.txt"}}
      ])

    calls = Message.tool_calls(msg)
    assert length(calls) == 2
    assert {"1", "read", %{"path" => "a.txt"}} in calls
    assert {"2", "read", %{"path" => "b.txt"}} in calls
  end

  test "extracts thinking content" do
    msg =
      Message.assistant([
        {:thinking, "Let me think..."},
        {:text, "Here's my answer"}
      ])

    assert Message.thinking(msg) == "Let me think..."
  end
end
