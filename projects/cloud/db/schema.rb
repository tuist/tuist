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

ActiveRecord::Schema[7.0].define(version: 2023_01_15_112317) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.string "name", limit: 40, null: false
    t.string "owner_type", null: false
    t.bigint "owner_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_accounts_on_name", unique: true
    t.index ["owner_id", "owner_type"], name: "index_accounts_on_owner_id_and_owner_type", unique: true
    t.index ["owner_type", "owner_id"], name: "index_accounts_on_owner"
  end

  create_table "command_events", force: :cascade do |t|
    t.string "name"
    t.string "subcommand"
    t.string "command_arguments"
    t.integer "duration"
    t.string "client_id"
    t.string "tuist_version"
    t.string "swift_version"
    t.string "macos_version"
    t.bigint "project_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "cacheable_targets"
    t.string "local_cache_target_hits"
    t.string "remote_cache_target_hits"
    t.index ["project_id"], name: "index_command_events_on_project_id"
  end

  create_table "invitations", force: :cascade do |t|
    t.string "inviter_type", null: false
    t.bigint "inviter_id", null: false
    t.string "invitee_email", null: false
    t.bigint "organization_id", null: false
    t.string "token", limit: 100, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invitee_email", "organization_id"], name: "index_invitations_on_invitee_email_and_organization_id", unique: true
    t.index ["inviter_type", "inviter_id"], name: "index_invitations_on_inviter"
    t.index ["organization_id"], name: "index_invitations_on_organization_id"
    t.index ["token"], name: "index_invitations_on_token", unique: true
  end

  create_table "organizations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "projects", force: :cascade do |t|
    t.string "name", limit: 40, null: false
    t.string "token", limit: 100, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "account_id", null: false
    t.string "remote_cache_storage_type"
    t.bigint "remote_cache_storage_id"
    t.index ["account_id"], name: "index_projects_on_account_id"
    t.index ["name", "account_id"], name: "index_projects_on_name_and_account_id", unique: true
    t.index ["remote_cache_storage_type", "remote_cache_storage_id"], name: "index_projects_on_remote_cache_storage"
    t.index ["token"], name: "index_projects_on_token", unique: true
  end

  create_table "roles", force: :cascade do |t|
    t.string "name"
    t.string "resource_type"
    t.bigint "resource_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name", "resource_type", "resource_id"], name: "index_roles_on_name_and_resource_type_and_resource_id"
    t.index ["resource_type", "resource_id"], name: "index_roles_on_resource"
  end

  create_table "s3_buckets", force: :cascade do |t|
    t.string "name", null: false
    t.string "access_key_id", null: false
    t.string "secret_access_key"
    t.string "iv"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "account_id", null: false
    t.string "region", null: false
    t.boolean "is_default", default: false
    t.bigint "default_project_id"
    t.index ["account_id"], name: "index_s3_buckets_on_account_id"
    t.index ["default_project_id"], name: "index_s3_buckets_on_default_project_id"
    t.index ["name", "account_id"], name: "index_s3_buckets_on_name_and_account_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "token", limit: 100, null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at", precision: nil
    t.datetime "remember_created_at", precision: nil
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at", precision: nil
    t.datetime "last_sign_in_at", precision: nil
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.string "confirmation_token"
    t.datetime "confirmed_at", precision: nil
    t.datetime "confirmation_sent_at", precision: nil
    t.string "unconfirmed_email"
    t.integer "failed_attempts", default: 0, null: false
    t.string "unlock_token"
    t.datetime "locked_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "last_visited_project_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["last_visited_project_id"], name: "index_users_on_last_visited_project_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["token"], name: "index_users_on_token", unique: true
  end

  create_table "users_roles", id: false, force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "role_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["role_id"], name: "index_users_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_users_roles_on_user_id_and_role_id"
    t.index ["user_id"], name: "index_users_roles_on_user_id"
  end

  add_foreign_key "projects", "accounts"
  add_foreign_key "s3_buckets", "accounts"
  add_foreign_key "users", "projects", column: "last_visited_project_id"
end
