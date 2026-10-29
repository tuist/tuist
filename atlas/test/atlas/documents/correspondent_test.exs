defmodule Atlas.Documents.CorrespondentTest do
  use Atlas.DataCase, async: true

  alias Atlas.Documents.Correspondent

  describe "changeset/2" do
    test "requires a name" do
      changeset = Correspondent.changeset(%Correspondent{}, %{})

      refute changeset.valid?
      assert errors_on(changeset) == %{name: ["can't be blank"]}
    end

    test "treats a blank name as missing" do
      changeset = Correspondent.changeset(%Correspondent{}, %{name: "   "})

      refute changeset.valid?
      assert errors_on(changeset) == %{name: ["can't be blank"]}
    end

    test "trims surrounding whitespace from the name" do
      changeset = Correspondent.changeset(%Correspondent{}, %{name: "  Acme GmbH  "})

      assert changeset.valid?
      assert get_change(changeset, :name) == "Acme GmbH"
    end

    test "enforces case-insensitive uniqueness" do
      assert {:ok, _} =
               %Correspondent{}
               |> Correspondent.changeset(%{name: "Acme"})
               |> Repo.insert()

      assert {:error, changeset} =
               %Correspondent{}
               |> Correspondent.changeset(%{name: "acme"})
               |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).name
    end
  end
end
