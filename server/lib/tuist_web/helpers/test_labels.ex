defmodule TuistWeb.Helpers.TestLabels do
  @moduledoc false

  use Gettext, backend: TuistWeb.Gettext

  alias Tuist.Projects.Project

  def module_label(%Project{build_system: :gradle}), do: dgettext("dashboard_tests", "Project")
  def module_label(_), do: dgettext("dashboard_tests", "Module")

  def modules_label(%Project{build_system: :gradle}), do: dgettext("dashboard_tests", "Projects")
  def modules_label(_), do: dgettext("dashboard_tests", "Modules")

  def test_modules_label(%Project{build_system: :gradle}), do: dgettext("dashboard_tests", "Test Projects")
  def test_modules_label(_), do: dgettext("dashboard_tests", "Test Modules")

  def suite_label(%Project{build_system: :gradle}), do: dgettext("dashboard_tests", "Class")
  def suite_label(_), do: dgettext("dashboard_tests", "Suite")

  def test_suite_label(%Project{build_system: :gradle}), do: dgettext("dashboard_tests", "Test Class")
  def test_suite_label(_), do: dgettext("dashboard_tests", "Test Suite")

  def test_suites_label(%Project{build_system: :gradle}), do: dgettext("dashboard_tests", "Test Classes")
  def test_suites_label(_), do: dgettext("dashboard_tests", "Test Suites")

  def scheme_label(%Project{build_system: :gradle}), do: dgettext("dashboard_tests", "Project")
  def scheme_label(_), do: dgettext("dashboard_tests", "Scheme")
end
