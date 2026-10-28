defmodule Atlas.Finance.CategoryTest do
  use Atlas.DataCase, async: true

  import Atlas.FinanceFixtures

  alias Atlas.Finance.Category

  describe "schema" do
    test "sets defaults" do
      category = %Category{}

      assert category.metadata == %{}
    end
  end

  describe "changeset/2" do
    test "requires a name" do
      changeset = Category.changeset(%Category{}, %{})

      refute changeset.valid?

      assert errors_on(changeset) == %{
               name: ["can't be blank"],
               slug: ["can't be blank"]
             }
    end

    test "normalizes names, optional strings, and slug" do
      changeset =
        Category.changeset(%Category{}, %{
          name: "  Cloud   Infrastructure  ",
          description: "  Hosting and compute  ",
          direction: " debit ",
          created_by_agent: " agent ",
          slug: " Cloud Infrastructure "
        })

      assert changeset.valid?
      assert get_change(changeset, :name) == "Cloud Infrastructure"
      assert get_change(changeset, :description) == "Hosting and compute"
      assert get_change(changeset, :direction) == "debit"
      assert get_change(changeset, :created_by_agent) == "agent"
      assert get_change(changeset, :slug) == "cloud-infrastructure"
    end

    test "derives slug from name" do
      changeset = Category.changeset(%Category{}, %{name: "Banking Fees"})

      assert changeset.valid?
      assert get_change(changeset, :slug) == "banking-fees"
    end

    test "rejects unsupported directions" do
      changeset = Category.changeset(%Category{}, %{name: "Revenue", direction: "outflow"})

      refute changeset.valid?
      assert "must be credit or debit" in errors_on(changeset).direction
    end

    test "rejects overly specific category names" do
      with_number = Category.changeset(%Category{}, %{name: "AWS May 2026"})
      too_many_words = Category.changeset(%Category{}, %{name: "Cloud Hosting For One Vendor Invoice"})

      refute with_number.valid?
      refute too_many_words.valid?
      assert "must be reusable and must not include numbers" in errors_on(with_number).name
      assert "must be broad enough to reuse across transactions" in errors_on(too_many_words).name
    end

    test "enforces unique slugs" do
      category = insert_finance_category!(%{name: "Software"})

      assert {:error, changeset} =
               %Category{}
               |> Category.changeset(%{name: "Software", slug: " #{category.slug} "})
               |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).slug
    end
  end

  describe "slugify/1" do
    test "returns lowercase url-safe slugs" do
      assert Category.slugify("Cloud & Infrastructure") == "cloud-infrastructure"
      assert Category.slugify("  Banking Fees  ") == "banking-fees"
      assert Category.slugify(nil) == nil
    end
  end

  describe "display_name/1" do
    test "normalizes raw extracted labels for analytics display" do
      assert Category.display_name("subscription") == "Software Subscription"
      assert Category.display_name("software_subscriptions") == "Software Subscription"
      assert Category.display_name("api") == "API"
      assert Category.display_name("Cloud Infrastructure") == "Cloud Infrastructure"
      assert Category.display_name("  ") == nil
    end
  end
end
