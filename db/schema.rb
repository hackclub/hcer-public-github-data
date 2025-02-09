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

ActiveRecord::Schema[8.0].define(version: 2025_02_09_234422) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "access_tokens", force: :cascade do |t|
    t.bigint "gh_id", null: false
    t.string "username", null: false
    t.string "access_token", null: false
    t.datetime "last_used_at"
    t.integer "core_rate_limit_remaining"
    t.datetime "core_rate_limit_reset_at"
    t.integer "search_rate_limit_remaining"
    t.datetime "search_rate_limit_reset_at"
    t.integer "graphql_rate_limit_remaining"
    t.datetime "graphql_rate_limit_reset_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["core_rate_limit_remaining", "core_rate_limit_reset_at"], name: "idx_on_core_rate_limit_remaining_core_rate_limit_re_41fd473f19"
    t.index ["gh_id"], name: "index_access_tokens_on_gh_id", unique: true
    t.index ["graphql_rate_limit_remaining", "graphql_rate_limit_reset_at"], name: "idx_on_graphql_rate_limit_remaining_graphql_rate_li_37af0ccffd"
    t.index ["last_used_at"], name: "index_access_tokens_on_last_used_at"
    t.index ["search_rate_limit_remaining", "search_rate_limit_reset_at"], name: "idx_on_search_rate_limit_remaining_search_rate_limi_7579e5db20"
    t.index ["username"], name: "index_access_tokens_on_username", unique: true
  end

  create_table "commits", primary_key: "sha", id: :string, force: :cascade do |t|
    t.bigint "gh_user_id", null: false
    t.datetime "committed_at", null: false
    t.text "message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["gh_user_id"], name: "index_commits_on_gh_user_id"
  end

  create_table "commits_gh_repos", id: false, force: :cascade do |t|
    t.string "commit_id", null: false
    t.bigint "gh_repo_id", null: false
    t.index ["commit_id", "gh_repo_id"], name: "index_commits_gh_repos_on_commit_id_and_gh_repo_id", unique: true
    t.index ["gh_repo_id", "commit_id"], name: "index_commits_gh_repos_on_gh_repo_id_and_commit_id"
  end

  create_table "gh_orgs", force: :cascade do |t|
    t.bigint "gh_id", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["gh_id"], name: "index_gh_orgs_on_gh_id", unique: true
    t.index ["name"], name: "index_gh_orgs_on_name", unique: true
  end

  create_table "gh_orgs_users", id: false, force: :cascade do |t|
    t.bigint "gh_user_id", null: false
    t.bigint "gh_org_id", null: false
    t.index ["gh_org_id", "gh_user_id"], name: "index_gh_orgs_users_on_gh_org_id_and_gh_user_id"
    t.index ["gh_user_id", "gh_org_id"], name: "index_gh_orgs_users_on_gh_user_id_and_gh_org_id", unique: true
  end

  create_table "gh_repos", force: :cascade do |t|
    t.bigint "gh_id", null: false
    t.string "name", null: false
    t.bigint "gh_user_id"
    t.bigint "gh_org_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["gh_id"], name: "index_gh_repos_on_gh_id", unique: true
    t.index ["gh_org_id"], name: "index_gh_repos_on_gh_org_id"
    t.index ["gh_user_id"], name: "index_gh_repos_on_gh_user_id"
    t.index ["name"], name: "index_gh_repos_on_name"
  end

  create_table "gh_users", force: :cascade do |t|
    t.bigint "gh_id", null: false
    t.string "username", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["gh_id"], name: "index_gh_users_on_gh_id", unique: true
    t.index ["username"], name: "index_gh_users_on_username", unique: true
  end

  add_foreign_key "commits", "gh_users"
  add_foreign_key "commits_gh_repos", "commits", primary_key: "sha"
  add_foreign_key "commits_gh_repos", "gh_repos"
  add_foreign_key "gh_repos", "gh_orgs"
  add_foreign_key "gh_repos", "gh_users"
end
