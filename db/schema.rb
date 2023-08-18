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

ActiveRecord::Schema[7.0].define(version: 2023_08_18_092024) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.string "name", limit: 40, null: false
    t.string "owner_type", null: false
    t.bigint "owner_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "legacy", default: true, null: false
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

  create_table "que_jobs", comment: "7", force: :cascade do |t|
    t.integer "priority", limit: 2, default: 100, null: false
    t.timestamptz "run_at", default: -> { "now()" }, null: false
    t.text "job_class", null: false
    t.integer "error_count", default: 0, null: false
    t.text "last_error_message"
    t.text "queue", default: "default", null: false
    t.text "last_error_backtrace"
    t.timestamptz "finished_at"
    t.timestamptz "expired_at"
    t.jsonb "args", default: [], null: false
    t.jsonb "data", default: {}, null: false
    t.integer "job_schema_version", null: false
    t.jsonb "kwargs", default: {}, null: false
    t.index ["args"], name: "que_jobs_args_gin_idx", opclass: :jsonb_path_ops, using: :gin
    t.index ["data"], name: "que_jobs_data_gin_idx", opclass: :jsonb_path_ops, using: :gin
    t.index ["job_schema_version", "queue", "priority", "run_at", "id"], name: "que_poll_idx", where: "((finished_at IS NULL) AND (expired_at IS NULL))"
    t.index ["kwargs"], name: "que_jobs_kwargs_gin_idx", opclass: :jsonb_path_ops, using: :gin
    t.check_constraint "char_length(\nCASE job_class\n    WHEN 'ActiveJob::QueueAdapters::QueAdapter::JobWrapper'::text THEN (args -> 0) ->> 'job_class'::text\n    ELSE job_class\nEND) <= 200", name: "job_class_length"
    t.check_constraint "char_length(last_error_message) <= 500 AND char_length(last_error_backtrace) <= 10000", name: "error_length"
    t.check_constraint "char_length(queue) <= 100", name: "queue_length"
    t.check_constraint "jsonb_typeof(args) = 'array'::text", name: "valid_args"
    t.check_constraint "jsonb_typeof(data) = 'object'::text AND (NOT data ? 'tags'::text OR jsonb_typeof(data -> 'tags'::text) = 'array'::text AND jsonb_array_length(data -> 'tags'::text) <= 5 AND que_validate_tags(data -> 'tags'::text))", name: "valid_data"
  end

  create_table "que_lockers", primary_key: "pid", id: :integer, default: nil, force: :cascade do |t|
    t.integer "worker_count", null: false
    t.integer "worker_priorities", null: false, array: true
    t.integer "ruby_pid", null: false
    t.text "ruby_hostname", null: false
    t.text "queues", null: false, array: true
    t.boolean "listening", null: false
    t.integer "job_schema_version", default: 1
    t.check_constraint "array_ndims(queues) = 1 AND array_length(queues, 1) IS NOT NULL", name: "valid_queues"
    t.check_constraint "array_ndims(worker_priorities) = 1 AND array_length(worker_priorities, 1) IS NOT NULL", name: "valid_worker_priorities"
  end

  create_table "que_values", primary_key: "key", id: :text, force: :cascade do |t|
    t.jsonb "value", default: {}, null: false
    t.check_constraint "jsonb_typeof(value) = 'object'::text", name: "valid_value"
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
    t.index ["account_id"], name: "index_s3_buckets_on_account_id"
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
