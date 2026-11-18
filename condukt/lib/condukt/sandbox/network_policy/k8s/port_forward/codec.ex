defmodule Condukt.Sandbox.NetworkPolicy.K8s.PortForward.Codec do
  @moduledoc false

  # Pure codec for the Kubernetes WebSocket port-forward wire
  # (`v4.channel.k8s.io` subprotocol, the same channel framing exec
  # uses, GA for port-forward since Kubernetes 1.30 / KEP-4006).
  #
  # Every WebSocket binary message is `<<channel::8, payload::binary>>`.
  # For a single forwarded port the API server uses two channels:
  #
  #   * channel 0 - the data stream (the bytes the pod port read/wrote)
  #   * channel 1 - an error stream (UTF-8 diagnostics, terminal)
  #
  # The API server's first message on each channel is a 2-byte
  # little-endian port number handshake that carries no application
  # payload. `Demux` strips exactly that first prefix per channel and
  # passes everything after through verbatim.
  #
  # This module is intentionally pure: all the protocol risk lives here
  # so it can be exhaustively unit tested without a cluster. The
  # GenServer that owns the socket only does Mint plumbing.

  @data_channel 0
  @error_channel 1

  defstruct awaiting_port: %{0 => true, 1 => true}

  @doc "Encodes an outbound application payload as a data-channel WebSocket binary body (`binary -> binary`)."
  def frame(payload) when is_binary(payload), do: <<@data_channel::8, payload::binary>>

  @doc "A fresh demultiplexer struct (no channel has seen its port handshake yet)."
  def new, do: %__MODULE__{}

  @doc """
  Feeds one decoded WebSocket binary message through the demultiplexer.

  Returns `{events, codec}` where `events` is a (possibly empty) list of
  `{:data, binary}` / `{:error, binary}` and `codec` is the updated
  struct. The per-channel 2-byte port handshake is consumed once and
  never surfaces as an event. Frames on unknown channels are ignored.
  """
  def feed(%__MODULE__{} = codec, <<channel::8, rest::binary>>) when channel in [@data_channel, @error_channel] do
    {payload, codec} = strip_port_handshake(codec, channel, rest)

    cond do
      payload == "" -> {[], codec}
      channel == @data_channel -> {[{:data, payload}], codec}
      true -> {[{:error, payload}], codec}
    end
  end

  def feed(%__MODULE__{} = codec, _other), do: {[], codec}

  defp strip_port_handshake(%__MODULE__{awaiting_port: awaiting} = codec, channel, bytes) do
    if Map.get(awaiting, channel, false) do
      codec = %{codec | awaiting_port: Map.put(awaiting, channel, false)}

      # The handshake is a 2-byte LE port. Anything beyond it in the
      # same frame is real payload (the API server normally sends the
      # handshake as its own frame, but never assume framing).
      case bytes do
        <<_port::little-16, payload::binary>> -> {payload, codec}
        _short -> {"", codec}
      end
    else
      {bytes, codec}
    end
  end
end
