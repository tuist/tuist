defmodule Tuist.Marketing.Pages do
  @moduledoc ~S"""
  This module handles the parsing and serving of static marketing pages like privacy policy
  and cookie policy. It uses NimblePublisher to parse markdown files from priv/marketing/pages/
  into Page structs that can be rendered by the web controllers.
  """
  use NimblePublisher,
    build: Tuist.Marketing.Pages.Page,
    from: Application.app_dir(:tuist, "priv/marketing/pages/*.md"),
    as: :pages,
    parser: Tuist.Marketing.Pages.PageParser,
    highlighters: [],
    earmark_options: [
      smartypants: false,
      postprocessor: &Tuist.Earmark.ASTProcessor.process/1
    ]

  def get_pages, do: @pages
end
