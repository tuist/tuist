defmodule Condukt.Test.Images do
  @moduledoc false

  def policy(owner, overrides \\ []) do
    Keyword.merge(
      [
        prepare: {__MODULE__, :prepare, [owner]},
        max_width: 2,
        max_height: 3,
        max_base64_bytes: 256,
        max_input_bytes: 16_384,
        max_pixels: 10_000,
        max_images: 4,
        max_total_base64_bytes: 1024,
        timeout: 1000
      ],
      overrides
    )
  end

  # A scripted decoder/fitter for the public session contract, not an image
  # decoder shipped with the library. Fixtures are complete, valid RGB PNGs.
  def prepare(bytes, policy, owner) do
    send(owner, {:prepared_image, bytes, policy.media_type})

    cond do
      bytes == png(2, 3) -> {:ok, bytes, "image/png", %{width: 2, height: 3}}
      bytes == png(9001, 1) -> {:ok, png(2, 1), "image/png", %{width: 2, height: 1}}
      true -> {:error, "decoder details must not reach the model"}
    end
  end

  def fail(_bytes, _policy, :raise), do: raise("private decoder detail")
  def fail(_bytes, _policy, :kill), do: Process.exit(self(), :kill)

  def fail(_bytes, _policy, {:wait, owner}) do
    send(owner, {:preparer_waiting, self()})
    receive do: (:finish -> {:error, :stopped})
  end

  def return(_bytes, _policy, result), do: result

  def attachment(bytes \\ png(2, 3)), do: %{type: :base64, media_type: "image/png", data: Base.encode64(bytes)}

  def png(width, height) do
    header = <<width::32, height::32, 8, 2, 0, 0, 0>>
    pixels = [<<0>>, :binary.copy(<<20, 80, 160>>, width)] |> IO.iodata_to_binary() |> :binary.copy(height)
    <<137, "PNG\r\n", 26, "\n">> <> chunk("IHDR", header) <> chunk("IDAT", :zlib.compress(pixels)) <> chunk("IEND", "")
  end

  defp chunk(type, bytes) do
    <<byte_size(bytes)::32, type::binary, bytes::binary, :erlang.crc32(type <> bytes)::32>>
  end
end
