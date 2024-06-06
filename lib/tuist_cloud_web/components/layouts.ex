defmodule TuistCloudWeb.Layouts do
  use TuistCloudWeb, :html

  embed_templates "layouts/*"

  def show_dashboard?() do
    if TuistCloud.Environment.on_premise?() do
      TuistCloud.Repo.timescale_available?()
    else
      false
    end
  end
end
