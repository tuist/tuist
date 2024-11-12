defmodule Tuist.Marketing.Pages do
  @moduledoc ~S"""
  This module handles the parsing and serving of static marketing pages like privacy policy
  and cookie policy. It uses NimblePublisher to parse markdown files from priv/marketing/pages/
  into Page structs that can be rendered by the web controllers.
  """
  alias Tuist.Marketing.Pages.Page
  alias Tuist.Marketing.Pages.PageParser
  alias Tuist.Earmark.ASTProcessor

  use NimblePublisher,
    build: Page,
    from: Application.app_dir(:tuist, "priv/marketing/pages/*.md"),
    as: :pages,
    parser: PageParser,
    highlighters: [],
    earmark_options: [
      postprocessor: &ASTProcessor.process/1
    ]

  def get_pages, do: @pages
end
