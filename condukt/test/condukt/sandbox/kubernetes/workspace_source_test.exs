defmodule Condukt.Sandbox.Kubernetes.WorkspaceSourceTest do
  use ExUnit.Case, async: true

  alias Condukt.Sandbox.Kubernetes.WorkspaceSource

  describe "normalize/1" do
    test "accepts a git URL string" do
      assert {:ok, %{git: "https://github.com/acme/repo.git", ref: nil}} =
               WorkspaceSource.normalize("https://github.com/acme/repo.git")
    end

    test "accepts keyword options" do
      assert {:ok, %{git: "git@github.com:acme/repo.git", ref: "main"}} =
               WorkspaceSource.normalize(git: "git@github.com:acme/repo.git", ref: "main")
    end

    test "accepts string-keyed maps" do
      assert {:ok, %{git: "https://github.com/acme/repo.git", ref: "v1"}} =
               WorkspaceSource.normalize(%{"git" => "https://github.com/acme/repo.git", "ref" => "v1"})
    end

    test "rejects empty git URLs" do
      assert {:error, ":workspace_source git URL cannot be empty"} =
               WorkspaceSource.normalize("  ")
    end

    test "rejects empty refs" do
      assert {:error, ":workspace_source :ref must be a non-empty string when provided"} =
               WorkspaceSource.normalize(git: "https://github.com/acme/repo.git", ref: "")
    end

    test "rejects non-keyword lists" do
      assert {:error, ":workspace_source keyword options must use atom keys"} =
               WorkspaceSource.normalize([{"git", "https://github.com/acme/repo.git"}])
    end
  end
end
