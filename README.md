# OrbitMath (rename me — see below)

A grid-linking math game. Click an adjacent number to add it to your chain,
double-click an adjacent number to multiply instead, and match the running
total to one of the cargo targets listed below the grid. Play solo against
an empty field, or host/join a live multiplayer match where two players
race over the *same* board to claim each target first.

Built with Ruby on Rails 7.1, Postgres, Hotwire (Turbo + Stimulus), and
ActionCable for real-time multiplayer. No JavaScript build step, no
Redis required for the MVP.

---

## ⚠️ Before you run this

This app was written in an environment with **no Ruby installed and no
network access**, so I could not run `bundle install`, migrate a real
database, or execute the test suite myself. Every file was written
carefully and the whole app follows standard, current Rails 7.1
conventions — but you should run the test suite yourself as the first
thing you do after setup (instructions below) to confirm everything
loads and passes before you build on top of it. If something doesn't
load, it's most likely a gem version mismatch or a typo I couldn't catch
without a Ruby interpreter — check the error message, it'll point
straight at the file.

## Requirements

- Ruby 3.2.2 (see `.ruby-version` — install via `rbenv`, `asdf`, or `rvm`)
- PostgreSQL 14+ running locally (`brew install postgresql@16 && brew services start postgresql@16` on a Mac)
- Bundler (`gem install bundler`)

## Setup

```bash
cd orbit_math
bin/setup
```

`bin/setup` will: install gems, create + migrate the database, seed demo
data, and clear logs/tmp. If it can't reach Postgres, start it first
(`brew services start postgresql@16`) and re-run.

Then start the app:

```bash
bin/dev
```

Open **http://localhost:3000**. Log in with one of the seeded demo
accounts (see below) or sign up fresh.

## Verify everything actually works

```bash
bin/rails test
```

This runs the full suite, including:

- `test/services/chain_evaluator_test.rb` — the math engine (left-to-right
  evaluation, adjacency rules, invalid-input rejection)
- `test/services/puzzle_generator_test.rb` — proves every generated
  puzzle is actually solvable and generation is deterministic per seed
- `test/services/claim_service_concurrency_test.rb` — spins up two real
  threads on two real DB connections that submit the *same winning
  chain at the same instant* and asserts only one of them wins the
  claim (this is the test that proves multiplayer can't be cheated by a
  race condition)
- `test/integration/multiplayer_simulation_test.rb` — plays out a
  complete two-player match end to end (generate puzzle → both players
  claim targets → game completes → stats update), plus edge cases
  (double-claim attempts, invalid chains)
- `test/models/user_test.rb`, `test/controllers/home_controller_test.rb`
  — basic model validation + homepage smoke tests

You can also narrate a full simulated match to your terminal:

```bash
bin/rails demo:multiplayer
```

This prints the generated grid, the target list, and a move-by-move log
of two demo players racing to claim every target, followed by the final
score and updated stats — a plain-English way to see the whole engine
work without opening a browser.

## Seeded demo accounts

`bin/rails db:seed` creates four accounts (password for all: `password123`):

| username | what it shows you |
|---|---|
| `nova`   | a finished solo run |
| `comet`  | one half of a finished multiplayer match |
| `pulsar` | the other half of that finished match |
| `meteor` | hosting an open multiplayer game, waiting in the lobby for someone to join |

Log in as `meteor` in one browser and `nova` (or a fresh signup) in
another/incognito window, go to **Multiplayer**, join meteor's open
game with its code, and play a live match to see real-time updates.

---

## How the game works

- **Grid**: an 8×8 board of digits 1–9 (configurable, see below).
- **Chain**: click a cell, then click a *neighboring* cell (including
  diagonals) to link it with `+`. Double-click a neighboring cell to
  link it with `×` instead. Click the last cell in your chain again to
  undo that link.
- **Evaluation is strictly left-to-right**, not standard order of
  operations — what you see drawn is exactly what you get:
  `3 → (+) → 5 → (×) → 2` evaluates as `(3 + 5) × 2 = 16`, not `13`.
- **Targets**: a handful of values are listed below the grid. Submit a
  chain whose value matches an unclaimed target to claim it.
- **Solo**: claim every target on the board at your own pace.
- **Multiplayer**: two players share one board. Whoever submits a
  matching chain *first* claims the target — if both submit the same
  winning chain within milliseconds of each other, a database-level
  lock (`GameSession#with_lock`, a Postgres `SELECT ... FOR UPDATE`)
  guarantees exactly one of them wins, never both.

## Architecture

```
app/services/
  puzzle_generator.rb    # builds the grid by seeding overlapping solvable
                          # chains first, then filling remaining cells
  chain_evaluator.rb      # validates + evaluates a submitted chain
                          # (server never trusts client-supplied values)
  claim_service.rb        # the one place a chain becomes a claim
  game_completion_service.rb  # finalizes a game, rolls results into stats
  game_state_presenter.rb # one JSON shape shared by HTTP responses,
                          # ActionCable broadcasts, and the initial page render
  puzzle_solver.rb        # brute-force chain finder, used by seeds/tests
                          # to prove puzzles are solvable (not used by
                          # real gameplay -- players solve it themselves!)

app/models/
  user.rb, puzzle.rb, game_session.rb, participant.rb, move.rb, user_stat.rb

app/channels/
  game_channel.rb          # one ActionCable stream per multiplayer GameSession

app/javascript/controllers/
  grid_controller.js       # click/double-click chain building + submit
  multiplayer_controller.js  # ActionCable subscription, hands updates to grid_controller
```

Puzzles are stored as reusable templates (`Puzzle`); a `GameSession`
(solo or multiplayer) plays against one Puzzle and tracks its own
`claims` independently, so the same board layout can theoretically be
replayed or shared without mutating shared state.

## Renaming the game

Everything user-facing reads from one config value. To rename:

```bash
# .env
GAME_NAME=YourNewName
GAME_TAGLINE=Your new tagline here
```

or edit the defaults directly in `config/application.rb`. That's it —
page titles, the homepage header, the PWA manifest, and every view all
pull from `Rails.application.config.x.game.name`. No find-and-replace
needed.

Grid size and target count are similarly configurable via
`GAME_GRID_SIZE` / `GAME_TARGET_COUNT` env vars if you want a smaller or
larger board later.

## Deploying as a web app

The app is a standard Rails monolith — deploy it anywhere that runs
Rails + Postgres (Render, Fly.io, Heroku, a VPS with Kamal, etc.).
A `Procfile` is included for platforms that use one. Set `DATABASE_URL`,
`RAILS_MASTER_KEY` (generate one with `bin/rails credentials:edit` if
you haven't already, or set `SECRET_KEY_BASE` directly), and the
`GAME_*` env vars above.

ActionCable is configured to use the in-process `async` adapter, which
works out of the box on a single server/dyno with zero extra
infrastructure. If you scale to multiple servers, switch
`config/cable.yml` production to the `redis` adapter (a one-line change,
commented inline in that file).

## Shipping to the App Store / Play Store

See **`MOBILE.md`** for the recommended path (wrapping this same Rails
app as a native shell via Capacitor) so you don't have to build and
maintain a second codebase.
