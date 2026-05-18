defmodule Tuist.Docs.Page do
  @moduledoc """
  Represents a compiled documentation page.
  """

  @enforce_keys [:slug, :title, :body, :source_path]
  defstruct [
    :slug,
    :title,
    :title_template,
    :description,
    :body,
    :body_template,
    :source_path,
    :markdown,
    :last_modified,
    headings: [],
    code_blocks: []
  ]
end
