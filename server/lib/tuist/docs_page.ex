defmodule Tuist.Docs.Page do
  @moduledoc """
  Represents a compiled documentation page.
  """

  @enforce_keys [:slug, :title, :body, :source_path]
  defstruct [:slug, :title, :title_template, :description, :body, :source_path, :markdown, headings: []]
end
