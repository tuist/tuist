defmodule Atlas.Documents.DocumentTypeTest do
  use Atlas.DataCase, async: true

  alias Atlas.Documents.DocumentType

  describe "changeset/2" do
    test "requires a name" do
      changeset = DocumentType.changeset(%DocumentType{}, %{})

      refute changeset.valid?
      assert errors_on(changeset) == %{name: ["can't be blank"]}
    end

    test "treats a blank name as missing" do
      changeset = DocumentType.changeset(%DocumentType{}, %{name: "   "})

      refute changeset.valid?
      assert errors_on(changeset) == %{name: ["can't be blank"]}
    end

    test "trims surrounding whitespace from the name" do
      changeset = DocumentType.changeset(%DocumentType{}, %{name: "  Contract  "})

      assert changeset.valid?
      assert get_change(changeset, :name) == "Contract"
    end

    test "enforces case-insensitive uniqueness" do
      assert {:ok, _} =
               %DocumentType{}
               |> DocumentType.changeset(%{name: "Contract"})
               |> Repo.insert()

      assert {:error, changeset} =
               %DocumentType{}
               |> DocumentType.changeset(%{name: "contract"})
               |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).name
    end
  end
end
