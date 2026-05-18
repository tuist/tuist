defmodule Tuist.Marketing.Pages do
  @moduledoc ~S"""
  This module handles the parsing and serving of static marketing pages like privacy policy
  and cookie policy. It uses NimblePublisher to parse markdown files from priv/marketing/pages/
  into Page structs that can be rendered by the web controllers.
  """

  use Tuist.Marketing.NimblePublisher.Content,
    build: Tuist.Marketing.Pages.Page,
    dev_from: Path.expand("../../../priv/marketing/pages/*.md", __DIR__),
    prod_from: Application.app_dir(:tuist, "priv/marketing/pages/*.md"),
    as: :pages,
    parser: Tuist.Marketing.Pages.PageParser,
    highlighters: [],
    html_converter: Tuist.Marketing.MDExConverter

  def get_pages, do: content_entries()
end
