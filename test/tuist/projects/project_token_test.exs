defmodule Tuist.Projects.ProjectTokenTest do
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias Tuist.Projects.ProjectToken
  use TuistTestSupport.Cases.DataCase

  describe "create_changeset/1" do
    test "ensures a project_id is present" do
      # Given
      token = %ProjectToken{}

      # When
      got = ProjectToken.create_changeset(token, %{encrypted_token_hash: "hash"})

      # Then
      assert "can't be blank" in errors_on(got).project_id
    end

    test "ensure an encrypted_token_hash is present" do
      # Given
      token = %ProjectToken{}

      # When
      got = ProjectToken.create_changeset(token, %{project_id: 1})

      # Then
      assert "can't be blank" in errors_on(got).encrypted_token_hash
    end

    test "ensures project_id and encrypted_token_hash are unique" do
      # Given
      token = %ProjectToken{}
      %{id: project_id} = ProjectsFixtures.project_fixture()

      changeset =
        ProjectToken.create_changeset(token, %{
          project_id: project_id,
          encrypted_token_hash: "hash"
        })

      changeset |> Repo.insert!()

      # When
      {:error, got} =
        Repo.insert(
          ProjectToken.create_changeset(%ProjectToken{}, %{
            project_id: project_id,
            encrypted_token_hash: "hash"
          })
        )

      # Then
      assert "has already been taken" in errors_on(got).encrypted_token_hash
    end
  end
end
