defmodule TuistWeb.Noora.Icon do
  @moduledoc false
  use Phoenix.Component

  @icons_path Path.join(File.cwd!(), "lib/tuist_web/components/noora/icons")
  @external_resource @icons_path

  for file <- File.ls!(@icons_path),
      Path.extname(file) == ".svg" do
    icon_name =
      file
      |> Path.basename(".svg")
      |> String.replace("-", "_")

    file_path = Path.join(@icons_path, file)
    content = File.read!(file_path)

    def unquote(String.to_atom(icon_name))(assigns) do
      assigns = assign(assigns, :content, unquote(content))

      ~H"""
      {Phoenix.HTML.raw(@content)}
      """
    end
  end
end
