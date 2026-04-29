defmodule Tuist.Marketing.Pages do
  @moduledoc ~S"""
  This module handles the parsing and serving of static marketing pages like privacy policy
  and cookie policy. It uses NimblePublisher to parse markdown files from priv/marketing/pages/
  into Page structs that can be rendered by the web controllers.
  """

  alias Tuist.Marketing.MDExConverter
  alias Tuist.Marketing.Pages.Page
  alias Tuist.Marketing.Pages.PageParser

  if Mix.env() == :dev do
    @pages_opts [
      build: Page,
      from: Path.expand("../../../priv/marketing/pages/*.md", __DIR__),
      parser: PageParser,
      highlighters: [],
      html_converter: MDExConverter
    ]

    def get_pages do
      Tuist.Marketing.RuntimeStore.entries(__MODULE__, @pages_opts)
    end
  else
    use NimblePublisher,
      build: Page,
      from: Application.app_dir(:tuist, "priv/marketing/pages/*.md"),
      as: :pages,
      parser: PageParser,
      highlighters: [],
      html_converter: MDExConverter

    def get_pages, do: @pages
  end
end
