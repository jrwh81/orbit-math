namespace :demo do
  desc "Play out a full simulated 2-player multiplayer match and narrate every claim to the console"
  task multiplayer: :environment do
    puts "== #{Rails.application.config.x.game.name}: simulated multiplayer match =="

    p1 = User.find_or_create_by!(username: "demo_astra") { |u| u.password = "password123"; u.display_name = "Astra" }
    p2 = User.find_or_create_by!(username: "demo_orion") { |u| u.password = "password123"; u.display_name = "Orion" }

    puzzle = PuzzleGenerator.call(difficulty: "intermediate", seed: rand(1..1_000_000))
    game = GameSession.create!(mode: :multiplayer, status: :active, puzzle: puzzle, host: p1, started_at: Time.current)
    game.participants.create!(user: p1, player_number: 1)
    game.participants.create!(user: p2, player_number: 2)

    puts "\nGrid (#{puzzle.size}x#{puzzle.size}):"
    puzzle.grid.each { |row| puts row.map { |v| v.to_s.rjust(2) }.join(" ") }

    puts "\nStarting targets: #{game.active_targets.map { |t| t["value"] }.join(", ")}"
    puts "Round length: #{game.time_limit_seconds}s (simulated instantly here, not in real time)"
    puts "Players: #{p1.name} vs #{p2.name}\n\n"

    # Seeds/demos run instantly rather than over real wall-clock time, so
    # this simulates "a round's worth of play" as a fixed number of
    # claims instead of actually waiting out the timer.
    simulated_claims = 9
    claim_count = 0

    # p1 claims 2 out of every 3 -- a clear winner without p2 going home
    # empty-handed. In a real game this split is decided by who spots
    # and clicks the chain first, not a script.
    simulated_claims.times do
      game.reload
      target = game.active_targets.find { |t| PuzzleSolver.find_path_for(game.active_grid, t["value"]) }
      break unless target

      path = PuzzleSolver.find_path_for(game.active_grid, target["value"])
      claimer = (claim_count % 3 == 2) ? p2 : p1
      result = ClaimService.call(game_session: game, user: claimer, coords: path[:coords], ops: path[:ops])
      chain_desc = path[:coords].map { |(r, c)| game.active_grid[r][c] }.join(path[:ops].first == "*" ? " x " : " + ")

      if result.success?
        replaced_with = result.replacement ? " -> new target #{result.replacement["value"]} rotates in" : ""
        puts "  #{claimer.name} claims #{target["value"]}  (chain: #{chain_desc})#{replaced_with}"
      else
        puts "  #{claimer.name} attempted #{target["value"]} but failed: #{result.message}"
      end

      claim_count += 1
    end

    puts "\n-- (simulated) time's up --"
    GameCompletionService.call(game.reload)

    puts "\nFinal score: #{p1.name} #{game.score_for(p1)} - #{game.score_for(p2)} #{p2.name}"
    puts "Winner: #{game.winner&.name || "tie"}"
    puts "Status: #{game.status}"
    puts "\n#{p1.name} stats: #{p1.stat.reload.attributes.slice("games_played", "games_won", "targets_claimed")}"
    puts "#{p2.name} stats: #{p2.stat.reload.attributes.slice("games_played", "games_won", "targets_claimed")}"
  end
end
