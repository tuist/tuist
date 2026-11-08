defmodule Pulse.Loki.PushProto do
  @moduledoc """
  Test-only encoder for Loki `POST /loki/api/v1/push` protobuf fixtures.

  Production decoding lives in Rust (`native/pulse_codec`); this is a
  separate, deliberately simple implementation so the tests check the
  decoder against a second reading of the schema rather than against
  itself. It is hand-written rather than generated because protobuf
  code generators need the `protoc` compiler installed, and the fixtures
  only ever need to encode these five messages.

  Field numbers mirror the upstream Loki definition (`pkg/push/push.proto`
  in grafana/loki). Proto3 defaults (empty strings, zero integers, empty
  repeated fields, absent messages) are omitted, as any encoder would.
  """

  import Bitwise

  alias Pulse.Loki.PushProto.Entry
  alias Pulse.Loki.PushProto.LabelPair
  alias Pulse.Loki.PushProto.PushRequest
  alias Pulse.Loki.PushProto.Stream
  alias Pulse.Loki.PushProto.Timestamp

  @doc false
  def encode(%PushRequest{streams: streams}), do: Enum.map(streams, &message(1, stream(&1)))

  defp stream(%Stream{labels: labels, entries: entries, hash: hash}) do
    [bytes(1, labels), Enum.map(entries, &message(2, entry(&1))), bytes(3, hash)]
  end

  defp entry(%Entry{timestamp: timestamp, line: line, structured_metadata: metadata}) do
    [
      if(timestamp, do: message(1, timestamp(timestamp)), else: []),
      bytes(2, line),
      Enum.map(metadata, &message(3, pair(&1)))
    ]
  end

  defp timestamp(%Timestamp{seconds: seconds, nanos: nanos}), do: [int(1, seconds), int(2, nanos)]

  defp pair(%LabelPair{name: name, value: value}), do: [bytes(1, name), bytes(2, value)]

  defp bytes(_field, ""), do: []
  defp bytes(field, value), do: message(field, value)

  defp message(field, iodata), do: [key(field, 2), varint(IO.iodata_length(iodata)), iodata]

  # int64/int32: negatives are sign-extended to 64 bits (ten-byte varints).
  defp int(_field, 0), do: []
  defp int(field, value), do: [key(field, 0), varint(value &&& 0xFFFF_FFFF_FFFF_FFFF)]

  defp key(field, wire_type), do: varint(field <<< 3 ||| wire_type)

  defp varint(value) when value < 0x80, do: <<value>>
  defp varint(value), do: [<<(value &&& 0x7F) ||| 0x80>>, varint(value >>> 7)]
end
