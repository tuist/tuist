defmodule Condukt.Sandbox.NetworkPolicy.K8s.PortForward.CodecTest do
  use ExUnit.Case, async: true

  alias Condukt.Sandbox.NetworkPolicy.K8s.PortForward.Codec

  defp port_handshake(channel, port), do: <<channel::8, port::little-16>>

  describe "frame/1" do
    test "prefixes the outbound payload with the data channel byte" do
      assert Codec.frame("hello") == <<0, "hello">>
    end
  end

  describe "feed/2 port handshake" do
    test "swallows the first frame on the data channel (the LE port)" do
      {events, _codec} = Codec.feed(Codec.new(), port_handshake(0, 15_002))
      assert events == []
    end

    test "swallows the first frame on the error channel too" do
      codec = Codec.new()
      {[], codec} = Codec.feed(codec, port_handshake(0, 15_002))
      {events, _codec} = Codec.feed(codec, port_handshake(1, 15_002))
      assert events == []
    end

    test "only the first frame per channel is treated as the handshake" do
      codec = Codec.new()
      {[], codec} = Codec.feed(codec, port_handshake(0, 15_002))
      {events, _codec} = Codec.feed(codec, <<0, "ndjson-line">>)
      assert events == [{:data, "ndjson-line"}]
    end

    test "payload riding along in the handshake frame is preserved" do
      {events, _codec} = Codec.feed(Codec.new(), <<0, 15_002::little-16, "early">>)
      assert events == [{:data, "early"}]
    end

    test "a short (truncated) handshake frame yields nothing" do
      {events, _codec} = Codec.feed(Codec.new(), <<0, 0x9A>>)
      assert events == []
    end
  end

  describe "feed/2 data + error demux" do
    setup do
      codec = Codec.new()
      {[], codec} = Codec.feed(codec, <<0, 15_002::little-16>>)
      {[], codec} = Codec.feed(codec, <<1, 15_002::little-16>>)
      %{codec: codec}
    end

    test "data-channel frames surface as {:data, _}", %{codec: codec} do
      assert {[{:data, "abc"}], _} = Codec.feed(codec, <<0, "abc">>)
    end

    test "error-channel frames surface as {:error, _}", %{codec: codec} do
      assert {[{:error, "boom"}], _} = Codec.feed(codec, <<1, "boom">>)
    end

    test "unknown channels are ignored", %{codec: codec} do
      assert {[], ^codec} = Codec.feed(codec, <<7, "whatever">>)
      assert {[], ^codec} = Codec.feed(codec, "")
    end

    test "an empty data frame produces no event", %{codec: codec} do
      assert {[], _} = Codec.feed(codec, <<0>>)
    end
  end
end
