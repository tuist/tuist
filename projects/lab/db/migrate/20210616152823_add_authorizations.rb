# frozen_string_literal: true
class AddAuthorizations < ActiveRecord::Migration[6.1]
  def change
    create_table("authorizations", force: :cascade) do |t|
      t.integer("user_id")
      t.string("provider")
      t.string("uid")
      t.string("email")

      # t.string "encrypted_token"
      # t.string "encrypted_secret"
      # t.string "encrypted_refresh_token"
      # t.boolean "expires"
      # t.datetime "expires_at"
      t.datetime("created_at", precision: 6, null: false)
      t.datetime("updated_at", precision: 6, null: false)
      t.index(
        ["provider", "uid"],
        name: "index_authorizations_on_provider_and_uid",
        unique: true
      )
      t.index(["provider"], name: "index_authorizations_on_provider")
      t.index(["uid"], name: "index_authorizations_on_uid")
      t.index(["user_id"], name: "index_authorizations_on_user_id")
    end
  end
end
