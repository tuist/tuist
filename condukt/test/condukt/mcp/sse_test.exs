defmodule Condukt.MCP.SSETest do
  use ExUnit.Case, async: true

  alias Condukt.MCP.SSE

  test "yields one event per blank-line-terminated block" do
    chunk = "event: message\ndata: hi\n\nevent: message\ndata: bye\n\n"
    {events, _state} = SSE.feed(SSE.new(), chunk)
    assert events == [%{event: "message", data: "hi"}, %{event: "message", data: "bye"}]
  end

  test "handles multi-line data fields" do
    chunk = "event: message\ndata: line1\ndata: line2\n\n"
    {events, _state} = SSE.feed(SSE.new(), chunk)
    assert events == [%{event: "message", data: "line1\nline2"}]
  end

  test "buffers across chunk boundaries" do
    {first, state} = SSE.feed(SSE.new(), "event: message\ndata: ")
    assert first == []
    {second, _state} = SSE.feed(state, "hello\n\n")
    assert second == [%{event: "message", data: "hello"}]
  end

  test "ignores comment lines and unknown fields" do
    chunk = ": this is a comment\nevent: message\nid: 123\ndata: x\n\n"
    {events, _state} = SSE.feed(SSE.new(), chunk)
    assert events == [%{event: "message", data: "x"}]
  end

  test "tolerates CRLF line endings" do
    chunk = "event: message\r\ndata: hi\r\n\r\n"
    {events, _state} = SSE.feed(SSE.new(), chunk)
    assert events == [%{event: "message", data: "hi"}]
  end
end
