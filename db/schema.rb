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

ActiveRecord::Schema[8.0].define(version: 2025_02_12_220047) do
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
    t.datetime "revoked_at"
    t.index ["core_rate_limit_remaining", "core_rate_limit_reset_at"], name: "idx_on_core_rate_limit_remaining_core_rate_limit_re_41fd473f19"
    t.index ["gh_id"], name: "index_access_tokens_on_gh_id", unique: true
    t.index ["graphql_rate_limit_remaining", "graphql_rate_limit_reset_at"], name: "idx_on_graphql_rate_limit_remaining_graphql_rate_li_37af0ccffd"
    t.index ["last_used_at"], name: "index_access_tokens_on_last_used_at"
    t.index ["revoked_at"], name: "index_access_tokens_on_revoked_at"
    t.index ["search_rate_limit_remaining", "search_rate_limit_reset_at"], name: "idx_on_search_rate_limit_remaining_search_rate_limi_7579e5db20"
    t.index ["username"], name: "index_access_tokens_on_username", unique: true
  end

  create_table "gh_commits", primary_key: "sha", id: :string, force: :cascade do |t|
    t.bigint "gh_user_id", null: false
    t.datetime "committed_at", null: false
    t.text "message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["gh_user_id"], name: "index_gh_commits_on_gh_user_id"
  end

  create_table "gh_commits_repos", id: false, force: :cascade do |t|
    t.string "gh_commit_id", null: false
    t.bigint "gh_repo_id", null: false
    t.index ["gh_commit_id", "gh_repo_id"], name: "index_gh_commits_repos_on_gh_commit_id_and_gh_repo_id", unique: true
    t.index ["gh_repo_id", "gh_commit_id"], name: "index_gh_commits_repos_on_gh_repo_id_and_gh_commit_id"
  end

  create_table "gh_orgs", force: :cascade do |t|
    t.bigint "gh_id", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "scrape_last_completed_at"
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
    t.text "description"
    t.string "homepage"
    t.string "language"
    t.datetime "repo_created_at"
    t.datetime "repo_updated_at"
    t.datetime "pushed_at"
    t.integer "stargazers_count", default: 0
    t.integer "forks_count", default: 0
    t.integer "watchers_count", default: 0
    t.integer "open_issues_count", default: 0
    t.integer "size", default: 0
    t.boolean "private", default: false
    t.boolean "archived", default: false
    t.boolean "disabled", default: false
    t.boolean "fork", default: false
    t.string "topics", default: [], array: true
    t.string "default_branch"
    t.boolean "has_issues", default: true
    t.boolean "has_wiki", default: true
    t.boolean "has_discussions", default: false
    t.datetime "scrape_last_completed_at"
    t.datetime "commits_scrape_last_completed_at"
    t.index ["archived"], name: "index_gh_repos_on_archived"
    t.index ["fork"], name: "index_gh_repos_on_fork"
    t.index ["forks_count"], name: "index_gh_repos_on_forks_count"
    t.index ["gh_id"], name: "index_gh_repos_on_gh_id", unique: true
    t.index ["gh_org_id"], name: "index_gh_repos_on_gh_org_id"
    t.index ["gh_user_id"], name: "index_gh_repos_on_gh_user_id"
    t.index ["language"], name: "index_gh_repos_on_language"
    t.index ["name"], name: "index_gh_repos_on_name"
    t.index ["private"], name: "index_gh_repos_on_private"
    t.index ["stargazers_count"], name: "index_gh_repos_on_stargazers_count"
    t.index ["topics"], name: "index_gh_repos_on_topics", using: :gin
  end

  create_table "gh_users", force: :cascade do |t|
    t.bigint "gh_id", null: false
    t.string "username", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "scrape_last_completed_at"
    t.string "name"
    t.string "email"
    t.text "bio"
    t.string "location"
    t.string "company"
    t.string "blog"
    t.string "twitter_username"
    t.string "avatar_url"
    t.integer "public_repos_count", default: 0
    t.integer "public_gists_count", default: 0
    t.integer "followers_count", default: 0
    t.integer "following_count", default: 0
    t.datetime "gh_created_at"
    t.datetime "gh_updated_at"
    t.index ["gh_id"], name: "index_gh_users_on_gh_id", unique: true
    t.index ["username"], name: "index_gh_users_on_username", unique: true
  end

  create_table "good_job_batches", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "description"
    t.jsonb "serialized_properties"
    t.text "on_finish"
    t.text "on_success"
    t.text "on_discard"
    t.text "callback_queue_name"
    t.integer "callback_priority"
    t.datetime "enqueued_at"
    t.datetime "discarded_at"
    t.datetime "finished_at"
    t.datetime "jobs_finished_at"
  end

  create_table "good_job_executions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "active_job_id", null: false
    t.text "job_class"
    t.text "queue_name"
    t.jsonb "serialized_params"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.text "error"
    t.integer "error_event", limit: 2
    t.text "error_backtrace", array: true
    t.uuid "process_id"
    t.interval "duration"
    t.index ["active_job_id", "created_at"], name: "index_good_job_executions_on_active_job_id_and_created_at"
    t.index ["process_id", "created_at"], name: "index_good_job_executions_on_process_id_and_created_at"
  end

  create_table "good_job_processes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "state"
    t.integer "lock_type", limit: 2
  end

  create_table "good_job_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "key"
    t.jsonb "value"
    t.index ["key"], name: "index_good_job_settings_on_key", unique: true
  end

  create_table "good_jobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "queue_name"
    t.integer "priority"
    t.jsonb "serialized_params"
    t.datetime "scheduled_at"
    t.datetime "performed_at"
    t.datetime "finished_at"
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "active_job_id"
    t.text "concurrency_key"
    t.text "cron_key"
    t.uuid "retried_good_job_id"
    t.datetime "cron_at"
    t.uuid "batch_id"
    t.uuid "batch_callback_id"
    t.boolean "is_discrete"
    t.integer "executions_count"
    t.text "job_class"
    t.integer "error_event", limit: 2
    t.text "labels", array: true
    t.uuid "locked_by_id"
    t.datetime "locked_at"
    t.index ["active_job_id", "created_at"], name: "index_good_jobs_on_active_job_id_and_created_at"
    t.index ["batch_callback_id"], name: "index_good_jobs_on_batch_callback_id", where: "(batch_callback_id IS NOT NULL)"
    t.index ["batch_id"], name: "index_good_jobs_on_batch_id", where: "(batch_id IS NOT NULL)"
    t.index ["concurrency_key"], name: "index_good_jobs_on_concurrency_key_when_unfinished", where: "(finished_at IS NULL)"
    t.index ["cron_key", "created_at"], name: "index_good_jobs_on_cron_key_and_created_at_cond", where: "(cron_key IS NOT NULL)"
    t.index ["cron_key", "cron_at"], name: "index_good_jobs_on_cron_key_and_cron_at_cond", unique: true, where: "(cron_key IS NOT NULL)"
    t.index ["finished_at"], name: "index_good_jobs_jobs_on_finished_at", where: "((retried_good_job_id IS NULL) AND (finished_at IS NOT NULL))"
    t.index ["labels"], name: "index_good_jobs_on_labels", where: "(labels IS NOT NULL)", using: :gin
    t.index ["locked_by_id"], name: "index_good_jobs_on_locked_by_id", where: "(locked_by_id IS NOT NULL)"
    t.index ["priority", "created_at"], name: "index_good_job_jobs_for_candidate_lookup", where: "(finished_at IS NULL)"
    t.index ["priority", "created_at"], name: "index_good_jobs_jobs_on_priority_created_at_when_unfinished", order: { priority: "DESC NULLS LAST" }, where: "(finished_at IS NULL)"
    t.index ["priority", "scheduled_at"], name: "index_good_jobs_on_priority_scheduled_at_unfinished_unlocked", where: "((finished_at IS NULL) AND (locked_by_id IS NULL))"
    t.index ["queue_name", "scheduled_at"], name: "index_good_jobs_on_queue_name_and_scheduled_at", where: "(finished_at IS NULL)"
    t.index ["scheduled_at"], name: "index_good_jobs_on_scheduled_at", where: "(finished_at IS NULL)"
  end

  create_table "tracked_gh_users", force: :cascade do |t|
    t.bigint "gh_id"
    t.string "username"
    t.jsonb "tags"
    t.datetime "scrape_last_requested_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "gh_commits", "gh_users"
  add_foreign_key "gh_commits_repos", "gh_commits", primary_key: "sha"
  add_foreign_key "gh_commits_repos", "gh_repos"
  add_foreign_key "gh_repos", "gh_orgs"
  add_foreign_key "gh_repos", "gh_users"
end
