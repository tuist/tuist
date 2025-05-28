## Project Overview
This project is an Elixir and Phoenix application.

## Common Commands
- **Build/Compile:** `mix compile`
- **Test All:** `mix test`
- **Test Single File:** `mix test path/to/test_file.exs`
- **Test Single Case:** `mix test path/to/test_file.exs:line_number_of_test`
- **Lint:** `mix credo`
- **Run Development Server:** `mise run dev` (requires `mise` to be installed and set up as per README.md)
- **Database Setup:** `mix ecto.setup` (creates DB, migrates, seeds)
- **Database Reset:** `mix ecto.reset`

## Code Style Guidelines
- **Formatting:** Follow standard Elixir and Phoenix conventions. Consider using an Elixir formatter.
- **Imports/Aliases:** Use `alias` for modules used multiple times. Avoid `import` unless for specific DSLs (e.g., Ecto.Query).
- **Types:** Utilize typespecs (`@spec`) for public functions.
- **Naming Conventions:**
    - Modules: PascalCase (e.g., `MyModule`)
    - Functions: snake_case (e.g., `my_function`)
    - Variables: snake_case (e.g., `my_variable`)
- **Error Handling:** Prefer tagged tuples `{:ok, value}` and `{:error, reason}` for functions that can fail. Use exceptions for unrecoverable errors.
- **Credo:** Adhere to rules in `.credo.exs`.
    - Timestamps in migrations should be `:timestamptz`.
    - Timestamps in `lib/` should be `:utc_datetime`.
- **Comments:** Add comments for complex logic or non-obvious code. Remove `TODO` comments once addressed.
