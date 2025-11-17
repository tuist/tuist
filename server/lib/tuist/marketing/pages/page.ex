defmodule Tuist.Marketing.Pages.Page do
  @moduledoc ~S"""
  This module defines the Page struct used to represent static pages in the Tuist marketing website.
  Pages are loaded from markdown files and parsed into this struct by NimblePublisher.
  """
  @enforce_keys [:excerpt, :slug, :title, :body]
  defstruct [
    :excerpt,
    :slug,
    :title,
    :body,
    :last_updated,
    :logo,
    :head_title,
    :head_description
  ]

  def build(_filename, attrs, body) do
    struct!(__MODULE__,
      excerpt: attrs["description"],
      slug: attrs["slug"],
      title: attrs["title"],
      body: body,
      last_updated: parse_date(attrs["last_updated"]),
      logo: attrs["logo"],
      head_title: attrs["head_title"],
      head_description: attrs["head_description"]
    )
  end

  defp parse_date(nil), do: nil

  defp parse_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp parse_date(_), do: nil
end
