defmodule Atlas.Documents.TagTest do
  use Atlas.DataCase, async: true

  alias Atlas.Documents.Tag

  describe "schema" do
    test "color defaults to neutral" do
      assert %Tag{}.color == "neutral"
    end
  end

  describe "changeset/2" do
    test "requires a name" do
      changeset = Tag.changeset(%Tag{}, %{})

      refute changeset.valid?
      assert errors_on(changeset) == %{name: ["can't be blank"]}
    end

    test "treats a blank name as missing" do
      changeset = Tag.changeset(%Tag{}, %{name: "   ", color: "information"})

      refute changeset.valid?
      assert errors_on(changeset) == %{name: ["can't be blank"]}
    end

    test "trims surrounding whitespace from the name" do
      changeset = Tag.changeset(%Tag{}, %{name: "  Finance  ", color: "information"})

      assert changeset.valid?
      assert get_change(changeset, :name) == "Finance"
    end

    test "accepts neutral and every palette color" do
      for color <- ["neutral" | Tag.colors()] do
        changeset = Tag.changeset(%Tag{}, %{name: "finance", color: color})
        assert changeset.valid?, "expected color #{color} to be valid"
      end
    end

    test "rejects an unsupported color" do
      changeset = Tag.changeset(%Tag{}, %{name: "finance", color: "rainbow"})

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).color
    end

    test "enforces case-insensitive uniqueness" do
      assert {:ok, _} = %Tag{} |> Tag.changeset(%{name: "Finance", color: "information"}) |> Repo.insert()

      assert {:error, changeset} =
               %Tag{} |> Tag.changeset(%{name: "finance", color: "success"}) |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).name
    end
  end

  describe "color_for/1" do
    test "returns a stable palette color regardless of case and whitespace" do
      color = Tag.color_for("Security")

      assert color in Tag.colors()
      assert Tag.color_for("security") == color
      assert Tag.color_for("  security  ") == color
    end
  end
end
