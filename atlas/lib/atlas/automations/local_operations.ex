defmodule Atlas.Automations.LocalOperations do
  @moduledoc "Secret-free domain adapters for capabilities without an existing serialization adapter."
  import Ecto.Query

  alias Atlas.Accounts
  alias Atlas.Accounts.Contact
  alias Atlas.Contracts
  alias Atlas.Inference
  alias Atlas.Inference.ModelBinding
  alias Atlas.Inference.Provider
  alias Atlas.Integrations
  alias Atlas.Integrations.GitHubApp
  alias Atlas.Licenses
  alias Atlas.MCP.Serializers.Accounts, as: AccountSerializer
  alias Atlas.MCP.Serializers.Tasks, as: TaskSerializer
  alias Atlas.Notes
  alias Atlas.Repo
  alias Atlas.Tasks
  alias Atlas.Users
  alias Atlas.Users.User

  @string %{"type" => "string"}
  @nullable %{"type" => ["string", "null"]}
  @id_input %{
    "type" => "object",
    "required" => ["id"],
    "properties" => %{"id" => @string},
    "additionalProperties" => false
  }
  @page_input %{
    "type" => "object",
    "properties" => %{"page" => %{"type" => "integer", "minimum" => 1, "maximum" => 100_000}},
    "additionalProperties" => false
  }
  @deleted %{
    "type" => "object",
    "required" => ["id", "deleted"],
    "properties" => %{"id" => @string, "deleted" => %{"enum" => [true]}},
    "additionalProperties" => false
  }
  @user_fields %{"id" => @string, "name" => @nullable, "email" => @string}
  @profile_fields %{
    "id" => @string,
    "name" => @string,
    "description" => @nullable,
    "upstream_provider" => @string,
    "upstream_model" => @string,
    "enabled" => %{"type" => "boolean"}
  }
  @profile_input_fields Map.delete(@profile_fields, "id")
  @provider_fields %{"id" => @string, "key" => @string}
  @app_fields %{"id" => @string, "name" => @nullable, "app_id" => @nullable, "installation_id" => @nullable}
  @license_fields %{"id" => @string, "account_id" => @string, "expires_on" => @string}
  @template_fields %{
    "template_set" => @string,
    "filename" => @string,
    "kind" => @string,
    "title" => @string,
    "byte_size" => %{"type" => "integer"}
  }

  def contracts do
    [
      contract("tasks.get", "tasks", [], @id_input, TaskSerializer.response_schema(), "Read a task by id."),
      contract(
        "tasks.delete",
        "tasks",
        [],
        @id_input,
        @deleted,
        "Delete a task; pending notification workers tolerate its absence.",
        true
      ),
      contract(
        "notes.delete",
        "notes",
        ["notes:write"],
        @id_input,
        @deleted,
        "Delete a Markdown note and its search record.",
        true
      ),
      contract(
        "accounts.delete",
        "accounts",
        ["accounts:write"],
        @id_input,
        @deleted,
        "Delete an account through the existing domain deletion boundary.",
        true
      ),
      contract(
        "accounts.contacts.get",
        "accounts",
        ["accounts:read"],
        @id_input,
        object(%{"contact" => AccountSerializer.contact_schema()}),
        "Read a contact."
      ),
      contract(
        "accounts.contacts.delete",
        "accounts",
        ["accounts:write"],
        @id_input,
        @deleted,
        "Delete a contact.",
        true
      ),
      contract(
        "users.list",
        "admin",
        ["admin:read"],
        @page_input,
        page_schema(@user_fields),
        "List users without grants or authentication credentials."
      ),
      contract(
        "users.get",
        "admin",
        ["admin:read"],
        @id_input,
        object(%{"user" => object(@user_fields)}),
        "Read user identity metadata, never credentials."
      ),
      contract(
        "licenses.list",
        "licenses",
        ["licenses:read", "admin:read"],
        @page_input,
        page_schema(@license_fields),
        "List license metadata without online keys or signed license contents."
      ),
      contract(
        "licenses.get",
        "licenses",
        ["licenses:read", "admin:read"],
        @id_input,
        object(%{"license" => object(@license_fields)}),
        "Read license metadata without returning credentials."
      ),
      contract(
        "licenses.create",
        "licenses",
        ["licenses:write", "admin:read"],
        object(%{"account_id" => @string, "expires_on" => @string}),
        object(%{"license" => object(@license_fields)}),
        "Issue a license after exact approval; return metadata only.",
        true
      ),
      contract(
        "licenses.extend",
        "licenses",
        ["licenses:write", "admin:read"],
        object(%{"id" => @string, "expires_on" => @string}),
        object(%{"license" => object(@license_fields)}),
        "Extend a license after exact approval; return metadata only.",
        true
      ),
      contract(
        "inference.profiles.list",
        "inference",
        ["inference:read"],
        @page_input,
        page_schema(@profile_fields),
        "List inference profile metadata, excluding tokens and provider keys."
      ),
      contract(
        "inference.profiles.get",
        "inference",
        ["inference:read"],
        @id_input,
        object(%{"profile" => object(@profile_fields)}),
        "Read an inference profile without credentials."
      ),
      contract(
        "inference.profiles.create",
        "inference",
        ["inference:write"],
        object(@profile_input_fields, ~w(name upstream_provider upstream_model)),
        object(%{"profile" => object(@profile_fields)}),
        "Create a profile without assigning built-in roles or issuing credentials.",
        true
      ),
      contract(
        "inference.profiles.update",
        "inference",
        ["inference:write"],
        object(Map.put(@profile_input_fields, "id", @string), ["id"]),
        object(%{"profile" => object(@profile_fields)}),
        "Update profile routing metadata without changing built-in roles or credentials.",
        true
      ),
      contract(
        "inference.profiles.delete",
        "inference",
        ["inference:write"],
        @id_input,
        @deleted,
        "Delete an inference profile through its domain boundary.",
        true
      ),
      contract(
        "inference.providers.list",
        "inference",
        ["inference:read"],
        @page_input,
        page_schema(@provider_fields),
        "List provider identifiers; never return keys, headers or endpoint configuration."
      ),
      contract(
        "inference.providers.get",
        "inference",
        ["inference:read"],
        @id_input,
        object(%{"provider" => object(@provider_fields)}),
        "Read provider identity metadata only."
      ),
      contract(
        "integrations.github_apps.list",
        "admin",
        ["admin:read"],
        @page_input,
        page_schema(@app_fields),
        "List GitHub app identity metadata without private keys or webhook secrets."
      ),
      contract(
        "integrations.github_apps.get",
        "admin",
        ["admin:read"],
        @id_input,
        object(%{"app" => object(@app_fields)}),
        "Read GitHub app identity metadata only."
      ),
      contract(
        "contracts.templates.get",
        "contracts",
        ["contracts:read"],
        object(%{"filename" => @string, "template_set" => @string}, ["filename"]),
        object(@template_fields),
        "Read template metadata, without generating a bearer download URL."
      )
    ]
  end

  defp contract(name, domain, permissions, input, output, description, approval \\ false) do
    %{
      "name" => name,
      "action" => name,
      "domain" => domain,
      "permissions" => permissions,
      "handler" => Atom.to_string(__MODULE__),
      "version" => 1,
      "requires_approval" => approval,
      "effect" => if(approval, do: "write", else: "read"),
      "execution_mode" => "local_transaction",
      "input_schema" => input,
      "output_schema" => output,
      "description" => description
    }
  end

  def execute("tasks.get", %{"id" => id}, _actor), do: fetch(Tasks.get_task(id), &%{task: TaskSerializer.task(&1)})

  def execute("tasks.delete", %{"id" => id}, actor),
    do: delete(Tasks.get_task(id), &Tasks.delete_task(&1, actor, interface: "worker"))

  def execute("notes.delete", %{"id" => id}, actor),
    do: delete(Notes.get_note(id), &Notes.delete_note(&1, audit_actor: actor, interface: "worker"))

  def execute("accounts.delete", %{"id" => id}, _actor),
    do: delete(Accounts.get_account(id), &Accounts.delete_account/1)

  def execute("accounts.contacts.get", %{"id" => id}, _actor),
    do: fetch(Repo.get(Contact, id), &%{contact: AccountSerializer.contact(&1)})

  def execute("accounts.contacts.delete", %{"id" => id}, _actor),
    do: delete(Repo.get(Contact, id), &Accounts.delete_contact/1)

  def execute("users.list", args, _actor), do: page(User, ~w(id name email), args)

  def execute("users.get", %{"id" => id}, _actor),
    do: fetch(Users.get_user(id), &%{user: fields(&1, ~w(id name email))})

  def execute("licenses.list", args, _actor) do
    {items, meta} = Licenses.list_licenses_page(page: args["page"] || 1, page_size: 20)
    {:ok, %{items: Enum.map(items, &license/1), total_count: meta.total_count}}
  end

  def execute("licenses.get", %{"id" => id}, _actor), do: fetch(Licenses.get_license(id), &%{license: license(&1)})
  def execute("licenses.create", args, _actor), do: result(Licenses.create_license(args), &%{license: license(&1)})

  def execute("licenses.extend", %{"id" => id} = args, _actor) do
    case Licenses.get_license(id) do
      nil -> {:error, :not_found}
      item -> result(Licenses.extend_license(item, Map.take(args, ["expires_on"])), &%{license: license(&1)})
    end
  end

  def execute("inference.profiles.list", args, _actor), do: page(ModelBinding, Map.keys(@profile_fields), args)

  def execute("inference.profiles.get", %{"id" => id}, _actor),
    do: fetch(Inference.get_profile(id), &%{profile: fields(&1, Map.keys(@profile_fields))})

  def execute("inference.profiles.create", args, _actor),
    do: result(Inference.create_profile(args), &%{profile: fields(&1, Map.keys(@profile_fields))})

  def execute("inference.profiles.update", %{"id" => id} = args, _actor) do
    case Inference.get_profile(id) do
      nil ->
        {:error, :not_found}

      item ->
        result(
          Inference.update_profile(item, Map.take(args, Map.keys(@profile_input_fields))),
          &%{profile: fields(&1, Map.keys(@profile_fields))}
        )
    end
  end

  def execute("inference.profiles.delete", %{"id" => id}, _actor),
    do: delete(Inference.get_profile(id), &Inference.delete_model_binding/1)

  def execute("inference.providers.list", args, _actor), do: page(Provider, Map.keys(@provider_fields), args)

  def execute("inference.providers.get", %{"id" => id}, _actor),
    do: fetch(Repo.get(Provider, id), &%{provider: fields(&1, Map.keys(@provider_fields))})

  def execute("integrations.github_apps.list", args, _actor), do: page(GitHubApp, Map.keys(@app_fields), args)

  def execute("integrations.github_apps.get", %{"id" => id}, _actor),
    do: fetch(Integrations.get_github_app(id), &%{app: fields(&1, Map.keys(@app_fields))})

  def execute("contracts.templates.get", args, _actor) do
    case Contracts.fetch_template(args["template_set"] || Contracts.default_template_set(), args["filename"]) do
      {:ok, template} -> {:ok, fields(template, Map.keys(@template_fields))}
      error -> error
    end
  end

  defp license(item), do: %{id: item.id, account_id: item.account_id, expires_on: Date.to_iso8601(item.expires_on)}
  defp result({:ok, item}, fun), do: {:ok, fun.(item)}
  defp result(other, _), do: other
  defp fetch(nil, _fun), do: {:error, :not_found}
  defp fetch(item, fun), do: {:ok, fun.(item)}
  defp delete(nil, _fun), do: {:error, :not_found}
  defp delete(item, fun), do: result(fun.(item), &%{id: &1.id, deleted: true})

  defp page(schema, keys, args) do
    query = from item in schema, order_by: [asc: item.id]
    {items, meta} = Flop.run(query, %Flop{page: args["page"] || 1, page_size: 20}, repo: Repo)
    {:ok, %{items: Enum.map(items, &fields(&1, keys)), total_count: meta.total_count}}
  end

  defp fields(item, keys), do: Map.new(keys, &{&1, Map.get(item, String.to_existing_atom(&1))})

  defp object(properties, required \\ nil),
    do: %{
      "type" => "object",
      "properties" => properties,
      "required" => required || Map.keys(properties),
      "additionalProperties" => false
    }

  defp page_schema(properties),
    do:
      object(%{"items" => %{"type" => "array", "items" => object(properties)}, "total_count" => %{"type" => "integer"}})
end
