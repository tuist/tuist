defmodule Tuist.MCP.Components.Tools.PreviewToolsTest do
  use ExUnit.Case, async: true

  alias Tuist.Accounts.Account
  alias Tuist.AppBuilds
  alias Tuist.AppBuilds.Preview
  alias Tuist.MCP.Components.Tools.PreviewSerializer
  alias Tuist.Projects.Project

  test "rejects an unsupported platform instead of removing the filter" do
    assert {:error, "supported_platforms contains an unsupported platform."} =
             PreviewSerializer.cast_supported_platforms(["not-a-platform"])
  end

  # MCP clients load the icon without the user's credentials, so its URL must
  # carry a token that the icon endpoint accepts for this preview.
  test "signs the icon URL with a stable icon token for the preview" do
    preview = %Preview{
      id: "0193b8c4-0000-7000-8000-000000000001",
      supported_platforms: [:ios],
      inserted_at: ~U[2026-11-16 10:00:00Z],
      app_builds: [],
      created_by_account: nil
    }

    project = %Project{name: "app", account: %Account{name: "acme"}}

    %{icon_url: icon_url} = PreviewSerializer.serialize(preview, project)
    %URI{path: path, query: query} = URI.parse(icon_url)

    assert path == "/acme/app/previews/#{preview.id}/icon.png"
    assert :ok = AppBuilds.verify_preview_icon_token(preview, URI.decode_query(query)["token"])

    # Image caches key on the URL, so it must not change between responses.
    assert PreviewSerializer.serialize(preview, project).icon_url == icon_url

    refute AppBuilds.verify_preview_icon_token(
             %{preview | id: "0193b8c4-0000-7000-8000-000000000002"},
             URI.decode_query(query)["token"]
           ) == :ok
  end
end
