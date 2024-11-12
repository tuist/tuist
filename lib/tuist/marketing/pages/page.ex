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
    :body
  ]

  def build(_filename, attrs, body) do
    struct!(__MODULE__,
      excerpt: attrs["description"],
      slug: attrs["slug"],
      title: attrs["title"],
      body: body
    )
  end
end
