defmodule Tuist.Marketing.OpenGraph do
  @moduledoc ~S"""
  This module provides utilities for generating open graph images for marketing routes.
  """
  use Phoenix.Component

  embed_templates "og_image/*"

  @max_length 35

  def generate_og_image(title, path) do
    {title_line_1, title_line_2, title_line_3} = og_image_title_lines(title)

    parent_directory = Path.dirname(path)

    if not File.exists?(parent_directory) do
      File.mkdir_p!(parent_directory)
    end

    {image, _} =
      %{
        title_line_1: title_line_1,
        title_line_2: title_line_2,
        title_line_3: title_line_3
      }
      |> template()
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()
      |> Vix.Vips.Operation.svgload_buffer!()

    Image.write!(image, path)
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def og_image_title_lines(title) do
    words = String.split(title, " ")

    {line1, line2, line3, _} =
      Enum.reduce(words, {"", "", "", 0}, fn word, {line1, line2, line3, line_number} ->
        cond do
          line_number == 0 and String.length(line1) + String.length(word) + 1 <= @max_length ->
            {line1 <> if(line1 == "", do: "", else: " ") <> word, line2, line3, 0}

          line_number <= 1 and String.length(line2) + String.length(word) + 1 <= @max_length ->
            {line1, line2 <> if(line2 == "", do: "", else: " ") <> word, line3, 1}

          line_number <= 2 and String.length(line3) + String.length(word) + 1 <= @max_length ->
            # credo:disable-for-next-line Credo.Check.Refactor.Nesting
            {line1, line2, line3 <> if(line3 == "", do: "", else: " ") <> word, 2}

          true ->
            {line1, line2, line3 <> "...", 3}
        end
      end)

    {String.trim(line1), String.trim(line2), String.trim(line3)}
  end
end
