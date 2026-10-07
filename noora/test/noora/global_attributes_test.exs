defmodule Noora.GlobalAttributesTest do
  @moduledoc """
  LiveView 1.2 emits `undefined attribute "..." for component ...` for every
  attribute a component neither declares nor lists in its
  `attr :rest, :global, include:` list. Consumers building with
  `mix compile --warnings-as-errors` fail on those, so the components that
  render a `<button>` or a link have to opt the relevant HTML attributes in.

  The check only runs at compile time — `@rest` collects undeclared assigns
  regardless at runtime — so these tests compile a template and assert on the
  diagnostics instead of on the rendered markup.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  @button_attributes ~s(type="submit" form="profile" disabled)
  @link_attributes ~s(target="_blank" rel="noopener")

  describe "components rendering a <button>" do
    test "button/1 accepts button attributes" do
      assert_no_warnings(~s(<.button label="Go" #{@button_attributes} />), Noora.Button)
    end

    test "neutral_button/1 accepts button attributes" do
      assert_no_warnings(~s(<.neutral_button label="Go" #{@button_attributes} />), Noora.Button)
    end

    test "button_group_item/1 accepts button attributes" do
      assert_no_warnings(~s(<.button_group_item label="Edit" #{@button_attributes} />), Noora.ButtonGroup)
    end

    test "button_dropdown/1 accepts button attributes" do
      assert_no_warnings(
        ~s(<.button_dropdown id="actions" label="More" #{@button_attributes}>x</.button_dropdown>),
        Noora.ButtonDropdown
      )
    end

    test "dismiss_icon/1 accepts button attributes" do
      assert_no_warnings(~s(<.dismiss_icon #{@button_attributes} />), Noora.DismissIcon)
    end
  end

  describe "components rendering a link" do
    test "button/1 accepts link attributes" do
      assert_no_warnings(~s(<.button label="Docs" href="/docs" #{@link_attributes} />), Noora.Button)
    end

    test "link_button/1 accepts link attributes" do
      assert_no_warnings(~s(<.link_button label="Docs" href="/docs" #{@link_attributes} />), Noora.Button)
    end

    test "button_group_item/1 accepts link attributes" do
      assert_no_warnings(~s(<.button_group_item label="Docs" href="/docs" #{@link_attributes} />), Noora.ButtonGroup)
    end

    test "tab_menu_horizontal_item/1 accepts link attributes" do
      assert_no_warnings(~s(<.tab_menu_horizontal_item label="Docs" href="/docs" #{@link_attributes} />), Noora.TabMenu)
    end

    test "sidebar_item/1 accepts link attributes" do
      assert_no_warnings(
        ~s(<.sidebar_item label="Docs" navigate="/docs" #{@link_attributes} />),
        Noora.Sidebar
      )
    end

    test "dropdown_item/1 accepts link attributes" do
      assert_no_warnings(
        ~s(<.dropdown_item value="1" label="Docs" navigate="/docs" #{@link_attributes} />),
        Noora.Dropdown
      )
    end
  end

  describe "attributes the component hardcodes stay overridable" do
    test "dismiss_icon/1 renders type once" do
      html = render_component(&Noora.DismissIcon.dismiss_icon/1, %{type: "reset"})

      assert html =~ ~s(type="reset")
      refute html =~ ~s(type="button")
      assert length(Regex.scan(~r/type=/, html)) == 1
    end

    test "button_dropdown/1 renders type once" do
      html =
        render_component(&Noora.ButtonDropdown.button_dropdown/1, %{
          id: "actions",
          label: "More",
          type: "submit",
          inner_block: []
        })

      main_button = html |> String.split(">") |> Enum.find(&(&1 =~ "main-button"))

      assert main_button =~ ~s(type="submit")
      refute main_button =~ ~s(type="button")
    end
  end

  test "a disabled button_group_item falls back to a button instead of a clickable link" do
    html = render_component(&Noora.ButtonGroup.button_group_item/1, %{label: "X", href: "/x", disabled: true})

    assert html =~ "<button"
    assert html =~ "disabled"
    refute html =~ "<a "
  end

  test "the check itself catches an attribute that is not opted in" do
    diagnostics = compile_template(~s(<.button label="Go" definitely-not-an-attribute="1" />), Noora.Button)

    assert Enum.any?(diagnostics, &(&1.message =~ ~s(undefined attribute "definitely-not-an-attribute")))
  end

  defp assert_no_warnings(template, component_module) do
    undefined_attributes =
      template
      |> compile_template(component_module)
      |> Enum.filter(&(&1.message =~ "undefined attribute"))
      |> Enum.map_join("\n", & &1.message)

    assert undefined_attributes == "", "#{template}\n\n#{undefined_attributes}"
  end

  defp compile_template(template, component_module) do
    module = :"Elixir.NooraGlobalAttributesProbe#{System.unique_integer([:positive])}"

    source = """
    defmodule #{inspect(module)} do
      use Phoenix.Component
      import #{inspect(component_module)}

      def render(assigns) do
        ~H"#{"\"\""}
        #{template}
        "#{"\"\""}
      end
    end
    """

    {{_result, diagnostics}, _io} =
      ExUnit.CaptureIO.with_io(:stderr, fn ->
        Code.with_diagnostics(fn -> Code.compile_string(source) end)
      end)

    :code.purge(module)
    :code.delete(module)

    diagnostics
  end
end
