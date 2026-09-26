defmodule TuistWeb.Helpers.TestLabels do
  @moduledoc """
  Provides build system-specific label helpers for test-related pages.

  Different build systems use different terminology (e.g. Gradle calls suites
  "classes" and schemes "projects", and neither Bazel nor Once has schemes at
  all). This module centralises those translations so the naming stays
  consistent across all dashboard pages.
  """

  use Gettext, backend: TuistWeb.Gettext

  alias Tuist.Projects.Project

  def module_label(%Project{build_system: :bazel}), do: dgettext("dashboard_tests", "Test target")
  def module_label(%Project{build_system: :once}), do: dgettext("dashboard_tests", "Target")
  def module_label(_), do: dgettext("dashboard_tests", "Module")

  def modules_label(%Project{build_system: :bazel}), do: dgettext("dashboard_tests", "Test Targets")
  def modules_label(%Project{build_system: :once}), do: dgettext("dashboard_tests", "Targets")
  def modules_label(_), do: dgettext("dashboard_tests", "Modules")

  def test_modules_label(%Project{build_system: :bazel}), do: dgettext("dashboard_tests", "Test Targets")
  def test_modules_label(%Project{build_system: :once}), do: dgettext("dashboard_tests", "Test Targets")
  def test_modules_label(_), do: dgettext("dashboard_tests", "Test Modules")

  def suite_label(%Project{build_system: :gradle}), do: dgettext("dashboard_tests", "Class")
  def suite_label(_), do: dgettext("dashboard_tests", "Suite")

  def test_suite_label(%Project{build_system: :gradle}), do: dgettext("dashboard_tests", "Test Class")
  def test_suite_label(_), do: dgettext("dashboard_tests", "Test Suite")

  def test_suites_label(%Project{build_system: :gradle}), do: dgettext("dashboard_tests", "Test Classes")
  def test_suites_label(_), do: dgettext("dashboard_tests", "Test Suites")

  def scheme_label(%Project{build_system: :bazel}), do: dgettext("dashboard_tests", "Invocation")
  def scheme_label(%Project{build_system: :gradle}), do: dgettext("dashboard_tests", "Project")
  # Once has no schemes. The shared `scheme` column carries the command the
  # run was invoked with, which is what every other Once page calls a Run.
  def scheme_label(%Project{build_system: :once}), do: dgettext("dashboard_tests", "Run")
  def scheme_label(_), do: dgettext("dashboard_tests", "Scheme")

  def test_run_label(%Project{build_system: :bazel}, scheme) when scheme not in [nil, ""], do: "bazel test #{scheme}"

  def test_run_label(%Project{build_system: :bazel}, _scheme), do: "bazel test"
  def test_run_label(_project, scheme) when scheme not in [nil, ""], do: scheme
  def test_run_label(_project, _scheme), do: dgettext("dashboard_tests", "Unknown")
end
