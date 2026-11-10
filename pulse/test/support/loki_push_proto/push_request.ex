defmodule Pulse.Loki.PushProto.PushRequest do
  @moduledoc false
  alias Pulse.Loki.PushProto

  defstruct streams: []

  @doc "Encode like a generated protobuf module: `{iodata, byte_size}`."
  def encode!(%__MODULE__{} = request) do
    iodata = PushProto.encode(request)
    {iodata, IO.iodata_length(iodata)}
  end
end
