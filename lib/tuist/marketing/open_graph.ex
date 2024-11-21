defmodule Tuist.Marketing.OpenGraph do
  @moduledoc ~S"""
  This module provides utilities for generating open graph images for marketing routes.
  """
  use Phoenix.Component

  embed_templates "og_image/*"

  @max_length 43

  def generate_og_image(title, path) do
    {title_line_1, title_line_2} = og_image_title_lines(title)

    {image, _} =
      template(%{title_line_1: title_line_1, title_line_2: title_line_2})
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()
      |> Vix.Vips.Operation.svgload_buffer!()

    Image.write!(image, path)
  end

  defp og_image_title_lines(title) do
    title
    |> String.split(" ")
    |> Enum.reduce_while({"", ""}, fn word, {title_line_1, title_line_2} ->
      cond do
        String.length(title_line_1 <> " " <> word) <= @max_length ->
          {:cont, {title_line_1 <> " " <> word, title_line_2}}

        String.length(title_line_2 <> " " <> word) <= @max_length - 3 ->
          {:cont, {title_line_1, title_line_2 <> " " <> word}}

        true ->
          {:halt, {title_line_1, title_line_2 <> "..."}}
      end
    end)
  end
end
