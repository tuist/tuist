defmodule Tuist.Marketing.Changelog.Entry do
  @moduledoc ~S"""
  This module defines the Entry struct used to represent changelog entries in the Tuist marketing website.
  Entries are loaded from markdown files in the priv/marketing/changelog directory and parsed into this struct.
  Each entry represents a change or update to the product and includes metadata like the category, date,
  title and description of the change.
  """
  @enforce_keys [:category, :date, :title, :body, :id]
  defstruct [
    :category,
    :date,
    :title,
    :body,
    :id
  ]

  def build(_filename, attrs, body) do
    title = String.trim_trailing(attrs["title"], ".")

    struct!(__MODULE__,
      category: attrs["category"],
      date: attrs["date"],
      title: title,
      id: attrs["id"],
      body: body
    )
  end
end
