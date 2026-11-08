defmodule TuistLabels.Renderer do
  @moduledoc "Label previews rendered with libvips; no Node runtime or shell interpolation."

  def render(%{"text" => text}, width, height)
      when is_binary(text) and byte_size(text) <= 480 do
    text = String.trim(text)

    if text == "" or String.length(text) > 120,
      do: throw({:api, 400, "Text must be 1–120 characters."})

    w = round(width * 203 / 25.4)
    h = round(height * 203 / 25.4)
    markup = text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    png =
      temporary(fn dir ->
        run([
          "text",
          "#{dir}/text.png",
          markup,
          "--font",
          "DejaVu Sans Bold",
          "--width",
          "#{w - 24}",
          "--height",
          "#{h - 20}",
          "--align",
          "centre",
          "--rgba"
        ])

        run([
          "gravity",
          "#{dir}/text.png",
          "#{dir}/padded.png",
          "centre",
          "#{w}",
          "#{h}",
          "--extend",
          "white"
        ])

        run(["flatten", "#{dir}/padded.png", "#{dir}/label.png", "--background", "255"])
        File.read!("#{dir}/label.png")
      end)

    {text, png}
  end

  def render(%{"png" => encoded}, _width, _height)
      when is_binary(encoded) and byte_size(encoded) <= 3_000_000 do
    with {:ok, png} <- Base.decode64(encoded),
         <<137, 80, 78, 71, 13, 10, 26, 10, 13::32, "IHDR", w::32, h::32, _::binary>> <- png,
         true <-
           w > 0 and h > 0 and w * h <= 4_000_000 and
             single_frame?(binary_part(png, 8, byte_size(png) - 8)) do
      result =
        temporary(fn dir ->
          File.write!("#{dir}/input.png", png)
          run(["flatten", "#{dir}/input.png", "#{dir}/label.png", "--background", "255"])
          File.read!("#{dir}/label.png")
        end)

      {"Uploaded PNG", result}
    else
      _ -> throw({:api, 400, "Provide a valid single-frame PNG (maximum 4 megapixels)."})
    end
  end

  def render(_, _, _), do: throw({:api, 400, "Each label needs text or a PNG."})

  defp single_frame?(<<_length::32, "acTL", _::binary>>), do: false
  defp single_frame?(<<0::32, "IEND", _crc::32>>), do: true

  defp single_frame?(<<length::32, _type::binary-size(4), rest::binary>>)
       when byte_size(rest) >= length + 4,
       do: single_frame?(binary_part(rest, length + 4, byte_size(rest) - length - 4))

  defp single_frame?(_), do: false

  defp temporary(fun) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "tuist-label-" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      )

    File.mkdir!(dir)
    File.chmod!(dir, 0o700)

    try do
      fun.(dir)
    after
      File.rm_rf!(dir)
    end
  end

  defp run(args) do
    # Small labels need no parallel workers; avoids observed vips 8.15/GLib crashes.
    case System.cmd("vips", ["--vips-concurrency=1" | args], stderr_to_stdout: true) do
      {_, 0} -> :ok
      _ -> throw({:api, 400, "Label image could not be rendered."})
    end
  end
end
