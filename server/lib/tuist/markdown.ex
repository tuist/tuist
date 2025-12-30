defmodule Tuist.Markdown do
  @moduledoc """
  Module for safe markdown rendering with HTML sanitization.

  This module provides functions to convert markdown to HTML with built-in
  sanitization to prevent XSS attacks and prompt injection attacks.
  """

  @doc """
  Converts markdown text to sanitized HTML.

  This function uses Earmark to parse markdown and HtmlSanitizeEx to sanitize
  the resulting HTML. If markdown parsing fails, the original text is returned.
  """
  @spec to_html(String.t()) :: String.t()
  def to_html(markdown) when is_binary(markdown) do
    case Earmark.as_html(markdown) do
      {:ok, html, _warnings} -> HtmlSanitizeEx.markdown_html(html)
      {:error, _html, _errors} -> markdown
    end
  end

  def to_html(_), do: ""
end
