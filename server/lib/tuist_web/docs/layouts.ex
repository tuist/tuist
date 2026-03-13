defmodule TuistWeb.Docs.Layouts do
  @moduledoc false
  use TuistWeb, :html
  use Noora

  alias Tuist.Docs.Paths

  embed_templates "layouts/*"

  defp docs_path(slug), do: Paths.public_path_from_slug(slug)
end
