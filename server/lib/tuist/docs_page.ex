defmodule Tuist.Docs.Page do
  @moduledoc """
  Represents a compiled documentation page.
  """

  @enforce_keys [:slug, :title, :body, :source_path]
  defstruct [:slug, :title, :description, :body, :source_path, headings: []]
end
