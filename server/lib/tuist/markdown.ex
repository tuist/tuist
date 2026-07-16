defmodule Tuist.Markdown do
  @moduledoc """
  Module for safe markdown rendering with HTML sanitization.

  This module provides functions to convert markdown to HTML with built-in
  sanitization to prevent XSS attacks and prompt injection attacks.
  """

  @doc """
  Converts markdown text to sanitized HTML.

  This function uses MDEx to parse markdown and HtmlSanitizeEx to sanitize
  the resulting HTML. If markdown parsing fails, the original text is returned.
  """
  def to_html(markdown) when is_binary(markdown) do
    markdown
    |> MDEx.to_html!()
    |> HtmlSanitizeEx.markdown_html()
  rescue
    _ -> markdown
  end

  def to_html(_), do: ""

  @doc """
  Escapes a string so it is safe to embed as HTML text, returning a plain binary.
  """
  def html_escape(text) do
    text
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
