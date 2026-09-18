defmodule Atlas.Engineering.ProjectsTest do
  use Atlas.DataCase, async: true

  alias Atlas.Audit.Activity
  alias Atlas.Engineering.Domains
  alias Atlas.Engineering.Projects
  alias Atlas.Repo

  describe "list_projects/0" do
    test "is empty by default" do
      assert Projects.list_projects() == []
    end
  end

  describe "create_project/1" do
    test "inserts a project with defaults" do
      assert {:ok, project} =
               Projects.create_project(%{"name" => "Cache", "visibility" => "public"})

      assert project.name == "Cache"
      assert project.visibility == :public
    end

    test "requires a name" do
      assert {:error, changeset} = Projects.create_project(%{"visibility" => "public"})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "update_project/2" do
    test "updates the description" do
      {:ok, project} =
        Projects.create_project(%{"name" => "Server", "visibility" => "public"})

      {:ok, updated} = Projects.update_project(project, %{"description" => "The API"})
      assert updated.description == "The API"
    end
  end

  describe "delete_project/1" do
    test "removes the project" do
      {:ok, project} =
        Projects.create_project(%{"name" => "Gone", "visibility" => "public"})

      assert {:ok, _} = Projects.delete_project(project)
      assert Projects.list_projects() == []
    end
  end

  describe "audit trail" do
    test "records project lifecycle activities" do
      {:ok, project} =
        Projects.create_project(%{"name" => "Audited", "visibility" => "public"})

      assert Repo.get_by!(Activity, action: "project.created", target_id: project.id)

      {:ok, _project} = Projects.update_project(project, %{"description" => "New"})

      assert Repo.get_by!(Activity, action: "project.updated", target_id: project.id)

      {:ok, domain} =
        Domains.create_domain(%{"name" => "Audited Domain", "visibility" => "public"})

      {:ok, _domain} = Projects.link_domain_to_project(project, domain.id)

      assert Repo.get_by!(Activity,
               action: "project.domain_linked",
               target_id: project.id
             )

      :ok = Projects.unlink_domain_from_project(project, domain.id)

      assert Repo.get_by!(Activity,
               action: "project.domain_unlinked",
               target_id: project.id
             )

      {:ok, repository} =
        Projects.create_repository_for_project(project, %{
          "owner" => "tuist",
          "name" => "atlas"
        })

      assert Repo.get_by!(Activity,
               action: "project.repository_linked",
               target_id: project.id
             )

      {:ok, _} = Projects.delete_repository_from_project(project, repository.id)

      assert Repo.get_by!(Activity,
               action: "project.repository_unlinked",
               target_id: project.id
             )

      {:ok, {webhook, _token}} =
        Projects.create_webhook(project, %{"name" => "Grafana", "source" => "grafana"})

      assert Repo.get_by!(Activity,
               action: "project.webhook_created",
               target_id: project.id
             )

      {:ok, _} = Projects.delete_webhook(project, webhook)

      assert Repo.get_by!(Activity,
               action: "project.webhook_deleted",
               target_id: project.id
             )

      {:ok, _} = Projects.delete_project(project)

      assert Repo.get_by!(Activity, action: "project.deleted", target_id: project.id)
    end
  end
end
