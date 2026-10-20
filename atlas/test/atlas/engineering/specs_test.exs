defmodule Atlas.Engineering.SpecsTest do
  use Atlas.DataCase, async: true

  alias Atlas.Engineering.Projects.Project
  alias Atlas.Engineering.Specs
  alias Atlas.Engineering.Specs.Comment
  alias Atlas.Repo
  alias Atlas.Users.User

  defp user(email \\ nil) do
    email = email || "specs-#{System.unique_integer([:positive])}@tuist.dev"

    %User{}
    |> User.changeset(%{email: email, name: "Spec Author"})
    |> Repo.insert!()
  end

  defp project! do
    name = "Specs test project #{System.unique_integer([:positive])}"

    %Project{}
    |> Project.changeset(%{name: name, visibility: :public})
    |> Repo.insert!()
  end

  test "creates a spec bound to an engineering project" do
    project = project!()

    assert {:ok, spec} =
             Specs.create_spec(
               %{
                 "title" => "Cross-domain claims",
                 "body" => "# Cross-domain claims\n\nProposal body.",
                 "engineering_project_id" => project.id
               },
               user()
             )

    assert spec.engineering_project_id == project.id
    assert spec.title == "Cross-domain claims"
    assert is_integer(spec.number)
  end

  test "assigns increasing public numbers" do
    project = project!()

    {:ok, first} =
      Specs.create_spec(
        %{
          "title" => "First",
          "body" => "# First\n\nBody.",
          "engineering_project_id" => project.id
        },
        user()
      )

    {:ok, second} =
      Specs.create_spec(
        %{
          "title" => "Second",
          "body" => "# Second\n\nBody.",
          "engineering_project_id" => project.id
        },
        user()
      )

    assert second.number > first.number
  end

  test "create_spec returns :unauthorized for a non-user" do
    assert {:error, :unauthorized} =
             Specs.create_spec(%{"title" => "x", "body" => "# x\n\nbody"}, nil)
  end

  test "updates a spec and records a revision" do
    project = project!()
    author = user()

    {:ok, spec} =
      Specs.create_spec(
        %{
          "title" => "Original",
          "body" => "# Original\n\nBody.",
          "engineering_project_id" => project.id
        },
        author
      )

    assert {:ok, updated} =
             Specs.update_spec(spec, %{"title" => "New title"}, author)

    assert updated.title == "New title"
    reloaded = Specs.get_spec!(spec.id)
    assert length(reloaded.revisions) >= 2
  end

  test "add_comment persists a comment" do
    project = project!()
    author = user()

    {:ok, spec} =
      Specs.create_spec(
        %{
          "title" => "Commented spec",
          "body" => "# Commented\n\nBody.",
          "engineering_project_id" => project.id
        },
        author
      )

    assert {:ok, %Comment{} = comment} = Specs.add_comment(spec, %{"body" => "Nice draft."}, author)

    assert comment.spec_id == spec.id
    assert comment.user_id == author.id
  end

  test "fetch_visible_spec_by_number hides private specs from anon" do
    project = project!()
    author = user()

    {:ok, spec} =
      Specs.create_spec(
        %{
          "title" => "Secret",
          "body" => "# Secret\n\nQuiet please.",
          "visibility" => "private",
          "engineering_project_id" => project.id
        },
        author
      )

    assert {:error, :not_found} = Specs.fetch_visible_spec_by_number(spec.number, nil)
    assert {:ok, _} = Specs.fetch_visible_spec_by_number(spec.number, author)
  end
end
