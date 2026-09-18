defmodule Atlas.Engineering.DomainsTest do
  use Atlas.DataCase, async: true

  alias Atlas.Engineering.Domains
  alias Atlas.Engineering.Projects

  describe "create_domain/1" do
    test "creates a domain" do
      assert {:ok, domain} = Domains.create_domain(%{"name" => "Cache", "visibility" => "public"})
      assert domain.name == "Cache"
    end

    test "links to a project when project_id is passed" do
      {:ok, project} = Projects.create_project(%{"name" => "Server", "visibility" => "public"})

      {:ok, domain} =
        Domains.create_domain(%{
          "name" => "Registry",
          "visibility" => "public",
          "project_id" => project.id
        })

      assert Enum.map(domain.projects, & &1.id) == [project.id]
    end
  end

  describe "link_domain_to_project/2 and unlink_domain_from_project/2" do
    test "attaches and detaches a domain" do
      {:ok, project} = Projects.create_project(%{"name" => "P", "visibility" => "public"})
      {:ok, domain} = Domains.create_domain(%{"name" => "D", "visibility" => "public"})

      :ok = Domains.link_domain_to_project(domain, project.id)
      assert Projects.list_domains_for_project(project.id) |> Enum.map(& &1.id) == [domain.id]

      :ok = Domains.unlink_domain_from_project(domain, project.id)
      assert Projects.list_domains_for_project(project.id) == []
    end
  end
end
