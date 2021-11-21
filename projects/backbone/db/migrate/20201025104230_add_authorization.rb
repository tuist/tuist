# frozen_string_literal: true

class AddAuthorization < ActiveRecord::Migration[6.0]
  def change
    create_table "authorizations", force: :cascade do |t|
      t.integer "user_id"
      t.string "provider"
      t.string "uid"
      t.string "email"
      t.timestamps
      t.index ["provider", "uid"], name: "index_authorizations_on_provider_and_uid"
      t.index ["provider"], name: "index_authorizations_on_provider"
      t.index ["uid"], name: "index_authorizations_on_uid"
      t.index ["user_id"], name: "index_authorizations_on_user_id"
    end
  end
end
