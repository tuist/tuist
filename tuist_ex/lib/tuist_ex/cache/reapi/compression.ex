defmodule TuistEx.Cache.Reapi.Compression do
  @moduledoc false

  @compile {:no_warn_undefined, :zstd}
  @threshold 1024

  def available?, do: Code.ensure_loaded?(:zstd)
  def eligible?(size), do: size >= @threshold and available?()

  def compress(binary) do
    compressed = :zstd.compress(binary, %{compressionLevel: 1}) |> IO.iodata_to_binary()
    if byte_size(compressed) < byte_size(binary), do: {compressed, true}, else: {binary, false}
  end

  def decompress(binary, limit) do
    {:ok, context} = :zstd.context(:decompress, %{windowLogMax: 26})

    try do
      {chunks, remaining} = decode(context, binary, [], limit)
      {:done, tail} = :zstd.finish(context, <<>>)
      {chunks, remaining} = append(tail, chunks, remaining)
      if remaining != 0, do: throw(:invalid_blob)
      chunks |> Enum.reverse() |> IO.iodata_to_binary()
    after
      :zstd.close(context)
    end
  end

  def wire_limit(size), do: size + div(size, 128) + 65_536

  defp decode(context, input, chunks, remaining) do
    case :zstd.stream(context, input) do
      {:continue, rest, output} ->
        {chunks, remaining} = append(output, chunks, remaining)
        decode(context, rest, chunks, remaining)

      {:continue, output} when byte_size(output) > 0 ->
        {chunks, remaining} = append(output, chunks, remaining)
        decode(context, <<>>, chunks, remaining)

      {:continue, <<>>} ->
        {chunks, remaining}
    end
  end

  defp append(output, chunks, remaining) do
    size = IO.iodata_length(output)
    if size > remaining, do: throw(:invalid_blob)
    {[output | chunks], remaining - size}
  end
end
