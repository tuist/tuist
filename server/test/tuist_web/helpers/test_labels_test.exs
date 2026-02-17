defmodule TuistWeb.Helpers.TestLabelsTest do
  use ExUnit.Case, async: true

  alias Tuist.Projects.Project
  alias TuistWeb.Helpers.TestLabels

  describe "module_label/1" do
    test "returns Module for any project" do
      assert TestLabels.module_label(%Project{build_system: :gradle}) == "Module"
      assert TestLabels.module_label(%Project{build_system: :xcode}) == "Module"
      assert TestLabels.module_label(nil) == "Module"
    end
  end

  describe "modules_label/1" do
    test "returns Modules for any project" do
      assert TestLabels.modules_label(%Project{build_system: :gradle}) == "Modules"
      assert TestLabels.modules_label(%Project{build_system: :xcode}) == "Modules"
    end
  end

  describe "test_modules_label/1" do
    test "returns Test Modules for any project" do
      assert TestLabels.test_modules_label(%Project{build_system: :gradle}) == "Test Modules"
      assert TestLabels.test_modules_label(%Project{build_system: :xcode}) == "Test Modules"
    end
  end

  describe "suite_label/1" do
    test "returns Class for gradle projects" do
      assert TestLabels.suite_label(%Project{build_system: :gradle}) == "Class"
    end

    test "returns Suite for xcode projects" do
      assert TestLabels.suite_label(%Project{build_system: :xcode}) == "Suite"
    end

    test "returns Suite for nil" do
      assert TestLabels.suite_label(nil) == "Suite"
    end
  end

  describe "test_suite_label/1" do
    test "returns Test Class for gradle projects" do
      assert TestLabels.test_suite_label(%Project{build_system: :gradle}) == "Test Class"
    end

    test "returns Test Suite for xcode projects" do
      assert TestLabels.test_suite_label(%Project{build_system: :xcode}) == "Test Suite"
    end
  end

  describe "test_suites_label/1" do
    test "returns Test Classes for gradle projects" do
      assert TestLabels.test_suites_label(%Project{build_system: :gradle}) == "Test Classes"
    end

    test "returns Test Suites for xcode projects" do
      assert TestLabels.test_suites_label(%Project{build_system: :xcode}) == "Test Suites"
    end
  end

  describe "scheme_label/1" do
    test "returns Project for gradle projects" do
      assert TestLabels.scheme_label(%Project{build_system: :gradle}) == "Project"
    end

    test "returns Scheme for xcode projects" do
      assert TestLabels.scheme_label(%Project{build_system: :xcode}) == "Scheme"
    end

    test "returns Scheme for nil" do
      assert TestLabels.scheme_label(nil) == "Scheme"
    end
  end
end
