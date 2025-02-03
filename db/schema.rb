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

ActiveRecord::Schema[8.0].define(version: 2025_02_03_210057) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "access_tokens", force: :cascade do |t|
    t.bigint "ghId", null: false
    t.string "username", null: false
    t.string "accessToken", null: false
    t.datetime "lastUsedAt"
    t.integer "coreRateLimitRemaining"
    t.datetime "coreRateLimitResetAt"
    t.integer "searchRateLimitRemaining"
    t.datetime "searchRateLimitResetAt"
    t.integer "graphqlRateLimitRemaining"
    t.datetime "graphqlRateLimitResetAt"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["coreRateLimitRemaining", "coreRateLimitResetAt"], name: "idx_on_coreRateLimitRemaining_coreRateLimitResetAt_9e2c89a985"
    t.index ["ghId"], name: "index_access_tokens_on_ghId", unique: true
    t.index ["graphqlRateLimitRemaining", "graphqlRateLimitResetAt"], name: "idx_on_graphqlRateLimitRemaining_graphqlRateLimitRe_9f037b7b1f"
    t.index ["lastUsedAt"], name: "index_access_tokens_on_lastUsedAt"
    t.index ["searchRateLimitRemaining", "searchRateLimitResetAt"], name: "idx_on_searchRateLimitRemaining_searchRateLimitRese_b71175a0a8"
    t.index ["username"], name: "index_access_tokens_on_username", unique: true
  end
end
