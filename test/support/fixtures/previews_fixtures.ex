defmodule Tuist.PreviewsFixtures do
  @moduledoc false

  alias Tuist.Previews
  alias Tuist.ProjectsFixtures

  def preview_fixture(opts \\ []) do
    project =
      Keyword.get_lazy(opts, :project, fn ->
        ProjectsFixtures.project_fixture()
      end)

    type = Keyword.get(opts, :type, :app_bundle)
    display_name = Keyword.get(opts, :display_name, "App")
    bundle_identifier = Keyword.get(opts, :bundle_identifier, "com.tuist.app")
    version = Keyword.get(opts, :version, "1.0.0")

    Previews.create_preview(%{
      project: project,
      type: type,
      display_name: display_name,
      bundle_identifier: bundle_identifier,
      version: version
    })
  end
end
