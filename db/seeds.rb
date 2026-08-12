# Seed data for local development / demoing the app.
#
#   bin/rails db:seed
#
# Creates four demo accounts (password for all: "password123"):
#   nova    - has one finished solo run
#   comet   \
#   pulsar  /  have one finished multiplayer match against each other
#   meteor  - is hosting an open multiplayer game, waiting for an opponent
#
# Every claim below goes through the real ClaimService, not a data dump,
# so this doubles as a smoke test that the core game engine actually
# works end to end -- including target rotation, since targets no longer
# sit still once claimed. Rounds are normally ended by the clock running
# out, but seeds run instantly rather than in real wall-clock time, so
# here we just simulate "a good round" as a fixed number of claims and
# finalize directly -- GameCompletionService doesn't care WHY a round is
# ending, only that it is.

puts "== Seeding demo data for #{Rails.application.config.x.game.name} =="

DEMO_PASSWORD = "password123"

def demo_user(username, first_name, last_name)
  User.find_or_create_by!(username: username) do |u|
    u.first_name = first_name
    u.last_name = last_name
    u.email = "#{username}@example.com"
    u.password = DEMO_PASSWORD
    u.password_confirmation = DEMO_PASSWORD
  end
end

# Plays `count` real claims into a game_session (via ClaimService, exactly
# like a real request would), picking a claimer for each one via the
# given block. Returns the number of claims actually made -- generation
# guarantees every active target is solvable, so this should only come
# up short if something regressed.
def play_claims!(game_session, count)
  made = 0

  count.times do |i|
    game_session.reload
    target = game_session.active_targets.find { |t| PuzzleSolver.find_path_for(game_session.active_grid, t["value"]) }
    break unless target

    path = PuzzleSolver.find_path_for(game_session.active_grid, target["value"])
    claimer = yield(i)
    ClaimService.call(game_session: game_session, user: claimer, coords: path[:coords], ops: path[:ops])
    made += 1
  end

  made
end

nova   = demo_user("nova", "Nova", "Starling")
comet  = demo_user("comet", "Comet", "Halley")
pulsar = demo_user("pulsar", "Pulsar", "Vega")
meteor = demo_user("meteor", "Meteor", "Storm")

puts "-- users ready: #{[nova, comet, pulsar, meteor].map(&:username).join(', ')}"

nova.update!(admin: true) unless nova.admin?
puts "-- nova is an admin (visit /admin after logging in as nova)"

# ---------------------------------------------------------------------------
# 1) A finished solo run for nova
# ---------------------------------------------------------------------------

solo_puzzle = PuzzleGenerator.call(seed: 111, difficulty: "beginner")
solo_session = GameSession.create!(mode: :solo, status: :active, puzzle: solo_puzzle, host: nova)
solo_session.participants.create!(user: nova, player_number: 1)

play_claims!(solo_session, 6) { nova }
GameCompletionService.call(solo_session.reload)
puts "-- solo run for nova: #{solo_session.claims.size} claimed, status=#{solo_session.status}"

# ---------------------------------------------------------------------------
# 2) A finished multiplayer match between comet and pulsar
# ---------------------------------------------------------------------------

mp_puzzle = PuzzleGenerator.call(seed: 222, difficulty: "intermediate")
mp_session = GameSession.create!(mode: :multiplayer, status: :active, puzzle: mp_puzzle, host: comet, started_at: Time.current)
mp_session.participants.create!(user: comet, player_number: 1)
mp_session.participants.create!(user: pulsar, player_number: 2)

# comet claims 2 out of every 3 -- a clear winner without pulsar going
# home with zero claims, simulating "comet was a bit faster all round"
play_claims!(mp_session, 9) { |i| i % 3 == 2 ? pulsar : comet }
GameCompletionService.call(mp_session.reload)
puts "-- multiplayer match comet vs pulsar: comet=#{mp_session.points_for(comet)}pts pulsar=#{mp_session.points_for(pulsar)}pts status=#{mp_session.status}"

# ---------------------------------------------------------------------------
# 3) An open multiplayer game hosted by meteor, waiting for an opponent
# ---------------------------------------------------------------------------

open_puzzle = PuzzleGenerator.call(seed: 333, difficulty: "advanced")
open_session = GameSession.create!(mode: :multiplayer, status: :waiting, puzzle: open_puzzle, host: meteor)
open_session.participants.create!(user: meteor, player_number: 1)
puts "-- open lobby game hosted by meteor, join code: #{open_session.join_code}"

puts "== Done. Log in as nova / comet / pulsar / meteor with password '#{DEMO_PASSWORD}' =="
