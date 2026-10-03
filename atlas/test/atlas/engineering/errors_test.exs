defmodule Atlas.Engineering.ErrorsTest do
  use Atlas.DataCase, async: true

  alias Atlas.Engineering.Errors
  alias Atlas.Engineering.Errors.Fingerprint
  alias Atlas.Engineering.Errors.Issue
  alias Atlas.Engineering.Errors.SentryEvent
  alias Atlas.Engineering.Projects

  describe "Fingerprint.compute/1 and Issue.deterministic_id/2" do
    test "produces a stable id for the same fingerprint" do
      event = SentryEvent.parse(%{"exception" => %{"values" => [%{"type" => "RuntimeError"}]}})
      fingerprint = Fingerprint.compute(event)

      assert String.length(fingerprint) == 64
      assert Issue.deterministic_id("p", fingerprint) == Issue.deterministic_id("p", fingerprint)
      refute Issue.deterministic_id("p", fingerprint) == Issue.deterministic_id("q", fingerprint)
    end
  end

  describe "list_issues/1" do
    test "returns [] on an empty database" do
      assert Errors.list_issues() == []
    end
  end

  describe "list_project_keys/1" do
    test "returns [] when no keys have been minted" do
      {:ok, project} =
        Projects.create_project(%{"name" => "Errors", "visibility" => "public"})

      assert Errors.list_project_keys(project.id) == []
    end
  end
end
