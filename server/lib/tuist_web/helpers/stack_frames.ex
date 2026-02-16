defmodule TuistWeb.Helpers.StackFrames do
  @moduledoc """
  Helper functions for parsing and rendering stack trace frames.
  """

  @doc """
  Parses a triggered_thread_frames string into a list of frame tuples.

  Each line is expected to be in the format: `{index}  {imageName}  {symbol}`
  where columns are separated by 2+ spaces.

  Returns a list of `{index, image_name, symbol}` tuples.
  """
  def parse_frames(frames_string) do
    frames_string
    |> String.split("\n", trim: true)
    |> Enum.map(&parse_frame_line/1)
  end

  defp parse_frame_line(line) do
    case Regex.run(~r/^(\s*\d+)\s{2,}(\S+)\s{2,}(.+)$/, line) do
      [_, index, image_name, symbol] -> {String.trim(index), image_name, symbol}
      _ -> {nil, nil, line}
    end
  end
end
