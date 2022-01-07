# frozen_string_literal: true

# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2021_10_22_072648) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "command_events", force: :cascade do |t|
    t.string("name")
    t.string("subcommand")
    t.json("params")
    t.integer("duration")
    t.string("client_id")
    t.string("tuist_version")
    t.string("swift_version")
    t.string("macos_version")
    t.datetime("created_at", precision: 6, null: false)
    t.datetime("updated_at", precision: 6, null: false)
    t.string("machine_hardware_name")
    t.boolean("is_ci")
    t.index(["client_id"], name: "index_command_events_on_client_id")
    t.index(["is_ci"], name: "index_command_events_on_is_ci")
    t.index(["macos_version"], name: "index_command_events_on_macos_version")
    t.index(["name"], name: "index_command_events_on_name")
    t.index(["subcommand"], name: "index_command_events_on_subcommand")
    t.index(["tuist_version"], name: "index_command_events_on_tuist_version")
  end
end
