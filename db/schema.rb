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

ActiveRecord::Schema[7.1].define(version: 2026_01_01_000017) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "game_sessions", force: :cascade do |t|
    t.integer "mode", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.bigint "puzzle_id", null: false
    t.bigint "host_id", null: false
    t.string "join_code"
    t.jsonb "claims", default: {}, null: false
    t.datetime "started_at"
    t.datetime "ended_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "active_targets", default: [], null: false
    t.integer "time_limit_seconds", default: 90, null: false
    t.jsonb "active_grid", default: [], null: false
    t.integer "next_id_seq", default: 1, null: false
    t.index ["host_id"], name: "index_game_sessions_on_host_id"
    t.index ["join_code"], name: "index_game_sessions_on_join_code", unique: true
    t.index ["mode", "status"], name: "index_game_sessions_on_mode_and_status"
    t.index ["puzzle_id"], name: "index_game_sessions_on_puzzle_id"
  end

  create_table "moves", force: :cascade do |t|
    t.bigint "game_session_id", null: false
    t.bigint "user_id", null: false
    t.jsonb "path", default: [], null: false
    t.jsonb "ops", default: [], null: false
    t.integer "result_value"
    t.boolean "claimed", default: false, null: false
    t.string "target_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["game_session_id", "claimed"], name: "index_moves_on_game_session_id_and_claimed"
    t.index ["game_session_id"], name: "index_moves_on_game_session_id"
    t.index ["user_id"], name: "index_moves_on_user_id"
  end

  create_table "participants", force: :cascade do |t|
    t.bigint "game_session_id", null: false
    t.bigint "user_id", null: false
    t.integer "player_number", default: 1, null: false
    t.integer "score", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["game_session_id", "player_number"], name: "index_participants_on_game_session_id_and_player_number", unique: true
    t.index ["game_session_id", "user_id"], name: "index_participants_on_game_session_id_and_user_id", unique: true
    t.index ["game_session_id"], name: "index_participants_on_game_session_id"
    t.index ["user_id"], name: "index_participants_on_user_id"
  end

  create_table "puzzles", force: :cascade do |t|
    t.integer "size", default: 8, null: false
    t.jsonb "grid", default: [], null: false
    t.jsonb "targets", default: [], null: false
    t.string "difficulty", default: "beginner", null: false
    t.integer "seed"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "user_difficulty_stats", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "difficulty", null: false
    t.integer "games_played", default: 0, null: false
    t.integer "games_won", default: 0, null: false
    t.integer "targets_claimed", default: 0, null: false
    t.integer "total_points", default: 0, null: false
    t.integer "best_solo_score", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "difficulty"], name: "index_user_difficulty_stats_on_user_id_and_difficulty", unique: true
    t.index ["user_id"], name: "index_user_difficulty_stats_on_user_id"
  end

  create_table "user_stats", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "games_played", default: 0, null: false
    t.integer "games_won", default: 0, null: false
    t.integer "targets_claimed", default: 0, null: false
    t.integer "total_score", default: 0, null: false
    t.integer "best_solo_score", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_user_stats_on_user_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "username", null: false
    t.string "email"
    t.string "password_digest"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "admin", default: false, null: false
    t.string "first_name"
    t.string "last_name"
    t.string "provider"
    t.string "uid"
    t.boolean "demo_mode_enabled", default: true, null: false
    t.boolean "guest", default: false, null: false
    t.boolean "name_claimed", default: false, null: false
    t.index ["admin"], name: "index_users_on_admin"
    t.index ["email"], name: "index_users_on_email", unique: true, where: "(email IS NOT NULL)"
    t.index ["guest"], name: "index_users_on_guest"
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "game_sessions", "puzzles"
  add_foreign_key "game_sessions", "users", column: "host_id"
  add_foreign_key "moves", "game_sessions"
  add_foreign_key "moves", "users"
  add_foreign_key "participants", "game_sessions"
  add_foreign_key "participants", "users"
  add_foreign_key "user_difficulty_stats", "users"
  add_foreign_key "user_stats", "users"
end
