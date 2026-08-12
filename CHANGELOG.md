# Changelog

## v12 — "How to Play" section on the homepage

- Added a **How to Play** section between the hero and the (login-gated)
  dashboard, visible to every visitor including logged-out ones -- the
  people who most need it, since they haven't played yet.
- Includes a small **illustrative demo board** built from the exact
  same CSS the real game uses (asteroid-shaped cells, the chain-line
  SVG overlay, the same "selected" styling) so it looks and feels
  authentic rather than a generic mockup, worked through one concrete
  example: 3 **+** 5 (a single-click/add link), then **&times;** 4
  (a double-click/multiply link) = 32. It's explicitly non-interactive
  and labeled "Example chain -- not a live game" so it's never
  confused for the real thing, and marked `aria-hidden` since the
  actual instructional content lives in the step list next to it, not
  in the decorative grid.
- Five-step written walkthrough covering click-to-add, double-click-to-
  multiply, automatic claiming (no submit button), and the fact that
  claimed cells get replaced with new numbers.
- New test coverage confirming the section actually renders for a
  logged-out visitor, the demo grid has its 4 cells, and the worked
  example's expression reads correctly.

Honest caveat: I can't take an actual screenshot of the live app or see
how this renders in a real browser -- worth a look once it's live to
confirm the layout, especially at mobile widths, actually reads the way
it's intended to.

## v11 — signup rework: first/last name, no display name, username-only in public

Redesigned the signup form to collect: first name, last name, username,
email, password (in that order) -- dropped "display name" entirely, per
feedback that it wasn't adding anything.

The interesting part was answering "what shows where": first/last name
are now **admin-only** (`User#full_name`), never shown to any other
player. Every player-facing surface -- nav bar, leaderboard (which is
fully public, no login required to view), in-game scoreboard, "hosted
by" labels -- shows **username only**. That was an explicit choice
given the leaderboard's public visibility, not just a default.

- **New `first_name`/`last_name` columns** on `users`; **`display_name`
  column removed** (new migration does both in one step, since nothing
  referenced it anymore by the time this was done).
- **`User#name`** now simply returns `username` -- and because every
  existing player-facing view already called `.name` rather than
  `.display_name` directly, this one change alone updated the nav bar,
  leaderboard, scoreboard, and every "hosted by" label with zero other
  view edits needed.
- **`User#full_name`** (new) joins first + last name, admin-only. Wired
  into the admin dashboard's recent-signups table, the admin users
  list, and the admin user detail page (alongside username and email,
  which were already admin-only).
- **Email is now required at signup**, first/last name too -- but
  enforced via a Rails **validation context** (`on: :signup`), not a
  blanket model requirement. This matters: the existing test suite (60+
  tests at this point) creates users directly via `User.create!` in
  dozens of places, almost none of which set an email, since it's been
  optional since the very first version. A blanket requirement would
  have broken most of that suite with no way for me to verify every
  fix without running it myself. The validation context means the
  signup form (`@user.save(context: :signup)`) genuinely enforces these
  fields, while every other `.create!` call -- tests, seeds, admin,
  future code -- is completely unaffected.
- New test coverage: a model-level test that a plain `User.create!`
  still works without first/last/email (the core guarantee the whole
  approach depends on), a test that the `:signup` context genuinely
  does reject an incomplete signup, a controller-level test that an
  incomplete signup POST actually fails, and a direct test that
  `#name` is provably always the username even when a real name is set
  (the privacy guarantee this whole feature is built around).
- Updated `db/seeds.rb` and `demo:multiplayer` to set first/last
  name + a real (fake) email on every demo account, since email is now
  meaningful admin-panel data worth having in seeded data.

## v10 — admin backend

A lightweight, custom-built admin panel — not the ActiveAdmin gem,
deliberately (see rationale below). No new dependencies, nothing that
can break in ways I can't test.

- **New `admin` boolean column on `users`** (new migration), gating an
  entire `/admin` namespace via a single `Admin::BaseController` that
  every admin controller inherits from — access control lives in
  exactly one place.
- **`/admin`** — dashboard: total users, total games, total targets
  claimed all-time, games currently in progress, a breakdown by
  mode/status/difficulty, and recent signups + recent games.
- **`/admin/users`** — every registered user with their stats
  (games played/won, targets claimed, best solo score) at a glance;
  click through to `/admin/users/:id` for that specific player's full
  game history.
- **`/admin/game_sessions`** — every game ever played, with a detail
  page per game showing players, scores, timing, and the most recent 50
  moves (including the human-readable expression via the existing
  `Move#expression` method, e.g. "3 + 5").
- **No self-serve promotion path, on purpose.** There's no UI to grant
  admin access, and the public signup form's strong params never
  included `:admin` (verified with a direct regression test that POSTs
  `admin: true` at signup and confirms it's silently ignored). The only
  way to grant admin is `bin/rails admin:promote[username]` from the
  command line -- also `admin:demote[username]` and `admin:list`.
- Real test coverage prioritizing the two things that actually matter
  for an admin panel: **access control** (every admin route rejects a
  logged-out visitor and a logged-in non-admin, tested against each
  route directly rather than just the guard mechanism in isolation) and
  **data correctness** (the numbers shown actually match what really
  happened, not just that the pages load without erroring).
- `db/seeds.rb` now makes `nova` an admin, so `/admin` has something to
  look at immediately after a fresh `bin/rails db:seed` locally.

Rationale for not using the ActiveAdmin gem: it pulls in Devise,
Ransack, Kaminari, Formtastic, and others -- a real dependency chain
that could easily hit its own Rails-7.1-compatibility surprise (see the
`TaggedLogging` incident a few versions back), with no way to verify
compatibility without a live bundler run. A custom admin panel achieves
the same goal here with zero new dependencies.

## v9.2 — fixed the REAL root cause behind v9.1's regression

v9.1 fixed a real bug (`add_target` returning `nil` too eagerly) but
the active target list kept shrinking anyway -- because that wasn't the
only bug. The actual root cause: `GameSession#next_target_id` computed
ids from a formula (`claims.size + active_targets.size + 1`) that
silently assumed exactly **one** new id gets issued per claim.

That assumption breaks the moment a claim also triggers a **repair**
(`ClaimService#repair_invalidated_targets` -- when cell regeneration
strands a *different* still-active target that shared one of the
changed cells). A claim with a repair issues *two* new ids in one pass;
the formula has no way to know that happened, so the next claim's
`next_target_id` call recomputes the same "next" number and collides
with an id already sitting in `active_targets`. Two targets end up
sharing an id. Claiming either one then removes **both** via
`reject { |t| t["id"] == target["id"] }` -- shrinking the list by an
extra slot on top of the normal one, compounding with every collision.

Fixed properly this time: `next_target_id` is now backed by a real
persistent counter (`next_id_seq`, new column) instead of a derived
formula, incrementing on every call -- including repeated calls within
the same claim. `ClaimService` was simplified to call
`@game_session.next_target_id` directly wherever a new id is needed
(for both the primary replacement and any repairs), removing a local
lambda-based counter that was working around the same underlying
problem without fixing it.

New test coverage: a direct unit test that `next_target_id` never
repeats across many sequential calls even without saving in between,
and a dedicated regression test across five seeds that explicitly
checks for duplicate ids after every single claim (not just list size,
which was the symptom -- duplicate ids are the actual invariant this
protects).

## v9.1 — fixed a real bug: the active target list could silently shrink

Caught by the test suite on a real multiplayer run: `active_targets.size`
dropped from 4 to 3 on Beginner difficulty and stayed there.

Root cause: `PuzzleGenerator.add_target`'s "avoid a value that's already
showing elsewhere on the list" preference was implemented as a hard
requirement (12 attempts, give up and return `nil` if none of them
avoided a duplicate). Beginner's board is small, addition-only, and
capped at values 1-20 -- it can easily run out of genuinely *new*
values well before it runs out of valid 2-cell chains. When `add_target`
returned `nil`, `ClaimService` had nothing to rotate in, so the active
list permanently lost a slot.

Fixed by making the duplicate-avoidance a soft preference with a
guaranteed fallback: try to avoid duplicates first, and if that fails,
accept any solvable chain regardless of duplicates. Duplicate target
values are explicitly allowed by design (this app has said so since
early on) -- silently shrinking the target list was never an acceptable
trade-off for "the list looks slightly more varied."

- Fixed one existing test whose assertion directly encoded the old,
  buggy expectation (`assert_nil` when every value was excluded) --
  updated to assert the new, correct behavior (always finds something).
- Added a dedicated regression test across 5 different seeds specifically
  on Beginner difficulty (the exact scenario that surfaced this), plus
  tightened the existing "stays solvable" invariant test to also assert
  the list never shrinks, not just that it stays solvable.

## v9 — asteroid theming: shapes, starfield, and a shatter effect

Purely visual polish, no gameplay/logic changes -- the instructions have
said "asteroids" since v1, but the board itself was just plain rounded
rectangles. This makes the visuals match the theme.

- **Cells now look like asteroids**, not blocks: irregular rock-like
  silhouettes (five different organic `border-radius` shapes, cycled
  deterministically by grid position via a new `data-shape` attribute so
  each cell keeps the same silhouette across re-renders instead of
  visibly reshaping on every click) plus a mottled rocky texture (a
  highlight + two "crater" gradients layered over the base color).
- **Space background** on every page: two soft nebula glows plus a
  scattered starfield, built entirely from layered CSS `radial-gradient`s
  (no images) tiled at a large enough size that the repeat isn't
  obviously grid-like.
- **Shatter effect on claim.** The `just-refreshed` cell animation
  (previously a card-flip, which didn't really fit the theme) is now a
  quick impact pulse, paired with `grid_controller.js#spawnShatterEffect`
  spawning a burst of small rock fragments that fly outward and fade for
  every cell that just got a new value -- the "asteroid breaking apart"
  moment the theme always implied but never showed. Reuses the same
  popup-layer overlay as the solve popup, for the same reason: it needs
  to survive the grid's own re-render, which would otherwise cut the
  animation off mid-flight.
- Avoided `background-attachment: fixed` for the starfield despite it
  being the more common approach for a "fixed" backdrop -- it's a known
  scroll-jank risk on iOS WebKit, which matters here since this app is
  meant to also run inside a Capacitor-wrapped mobile shell.

## v8 — solve popups + the grid itself now evolves

- **Floating solve popup.** The instant a chain claims a target, a
  translucent "3 + 5 = 8" label pops up right at the location on the
  board where it happened, floats upward, and fades out. Positioned
  from the actual centroid of the cells you just linked, not a fixed
  spot -- computed client-side from the path before it's cleared.
- **The grid itself now evolves over a round.** Previously the board's
  digits were static for the whole round; only the target list rotated.
  Now, the instant a chain claims a target, every cell that was part of
  that winning chain gets a brand-new digit (guaranteed different from
  what it was), with a "flip" animation on exactly those cells. Claiming
  a chain genuinely "uses up" those numbers.
- **This required giving each `GameSession` its own live, mutable grid**
  (`active_grid`, new column) separate from the immutable `Puzzle`
  template -- the same pattern already used for `active_targets`.
  `ChainEvaluator` now validates every submitted move against this live
  grid, not the original template, since once cells start changing the
  template no longer reflects what the player is actually looking at.
- **The hard part: repairing accidentally-broken targets.** Multiple
  targets are allowed to share the same cells by design (that's what
  makes overlapping solution chains possible). Regenerating a winning
  chain's cells can therefore silently strand a *different*, still-active
  target that happened to depend on one of those same cells. `ClaimService`
  now re-checks every remaining target against the updated grid after
  each claim and swaps in a fresh (verified-solvable) replacement for
  any that broke -- "there should always be an answer available" is a
  guarantee this app makes, not just a nice-to-have, so this couldn't be
  skipped.
- Fixed one real correctness risk caught during implementation: mutating
  `active_grid`'s cached array in place and reassigning the same object
  reference risks ActiveRecord's dirty tracking silently not detecting
  the change on save. Fixed by always working from a fresh duplicate,
  the same pattern the `claims` hash already used via `.merge`.
- Also cleaned up a DRY violation caught in review: `ClaimService`'s
  multi-id counter (needed since one claim can require several new
  target ids -- the primary replacement plus any repairs) was
  reimplementing `GameSession#next_target_id`'s exact formula inline
  instead of deriving from it, risking silent drift if either changed
  later.
- New test coverage: winning-chain cells actually change value,
  untouched cells provably don't, and -- the one that matters most --
  a 20-claim run on a small (high cell-overlap) board asserting that
  every remaining active target stays solvable after every single
  claim. Swept every other test file, `seeds.rb`, and the demo rake
  task to read the live `active_grid` instead of the now-potentially-stale
  `puzzle.grid` wherever multiple sequential claims happen in a loop.

## v7 — end-of-round stats screen + auto-return to home

- **Stats modal on completion.** Instead of a small inline banner, the
  round now ends with a full-screen modal showing a result headline plus
  three personal highlights for the round: targets claimed, **longest
  chain**, and highest single value claimed. Same JS-detects-the-
  transition mechanism as before (no reliance on a page reload), just a
  richer screen.
- **`GameSession#longest_chain_for(user)`** / **`#highest_value_claimed_by(user)`**
  compute these directly from that session's own `Move` records (not
  global `UserStat`), so they're specifically "how you did in THIS
  round" numbers, not lifetime stats.
- **`GameStatePresenter`** now includes a `summary` field once the game
  is completed -- a per-user hash of `{claims, longest_chain, highest_value}`,
  keyed by user id so the client can pull out "mine" regardless of
  solo/multiplayer.
- **Auto-return to home.** The stats modal automatically sends the
  player back to the homepage after 6 seconds -- "Play again" and
  "Continue" buttons both skip the wait for anyone who doesn't want to
  sit through it. By the time they land on the homepage, their
  `UserStat` dashboard there already reflects the round that just
  finished, since `GameCompletionService` runs server-side before the
  client ever sees the completion response.
- New test coverage: `GameSession` stats methods (including that a
  player who claimed nothing correctly reads zero, even when their
  opponent has plenty of claims on the same session), and a dedicated
  `GameStatePresenterTest` covering the new `summary` field and
  confirming the old `claimed`/`claimed_by` per-target flags are gone
  from the targets payload for good.

## v6.2 — fixed a real bug: explicit time_limit_seconds was getting silently clobbered

The test suite caught a genuine bug: `GameSession#initialize_round!`
unconditionally overwrote `time_limit_seconds` with the difficulty
preset's value on every new record, even when the caller explicitly
passed a different one. In practice this never bit real gameplay (no
controller ever passes `time_limit_seconds:` explicitly, they all rely
on the difficulty preset), but it meant nothing could ever override the
timer -- including tests that wanted a short, controllable round length.
Fixed by only applying the preset when the record still has the raw
column default, not something the caller explicitly set.

Also tightened two test assertions that were flaky by construction:
they asserted `time_remaining_seconds` equals the round length *exactly*
immediately after creation, but real wall-clock time inevitably elapses
during test execution (and `time_remaining_seconds` floors to a whole
second), so an occasional one-or-two-second-under reading was always
possible even with correct app behavior. Switched to `assert_in_delta`.

## v6.1 — flat 90-second rounds

All four difficulty tiers now use a **90-second round** (was a tiered
60/90/120/150s scaling with difficulty). `PuzzleGenerator::DIFFICULTY_LEVELS`
and the `game_sessions.time_limit_seconds` column default were updated
accordingly. Grid size, chain complexity, and value ceiling still scale
per difficulty as before -- only the clock length changed.

## v6 — timer-based rounds, not claim counts

Follow-up feedback on v5: the win condition should be a countdown clock,
not "first to N claims." Reworked the whole completion mechanism.

- **`GameSession#time_limit_seconds`** (replaces `claim_goal`) is set
  per-difficulty (Beginner: 60s, Intermediate: 90s, Advanced: 120s,
  Expert: 150s) the same way grid size and value ceiling are.
- **`GameSession#time_expired?`** / **`#time_remaining_seconds`**
  replace `goal_reached?`. A round ends when the clock runs out, not
  when anyone reaches a count -- multiplayer is decided by whoever has
  the higher score (claims) at that moment, exactly like before, just
  triggered by time instead of a threshold.
- **Live countdown clock** on the board (`renderTimer`), ticking client-
  side every second and re-syncing to the server's authoritative
  `time_remaining_seconds` on every fresh state (own move, opponent's
  move, or the finish call) so client/server clock drift never
  accumulates across a round. Turns red and pulses in the final 10
  seconds.
- **New `finish` endpoint** (`POST /solo_games/:id/finish`,
  `POST /multiplayer/:id/finish`), called automatically by the client
  the instant its own countdown hits zero. Idempotent -- safe to call
  even if the round was already finalized another way. For multiplayer,
  broadcasts the final state to both players so a slightly-lagging
  opponent's clock still ends in sync.
- **Server-side enforcement is independent of the client's clock**:
  `MovesController` checks `time_expired?` before *and* after processing
  every claim attempt, so a client with a fast clock can't grab extra
  time and a client with a slow one just gets told the round already
  ended. The countdown is a UI convenience; the server is the actual
  authority.
- Solo rounds are no longer pass/fail against a goal -- every completed
  timed run counts toward `games_won`/stats, with `best_solo_score`
  as the real measure of how you did.
- Real time-travel test coverage (`ActiveSupport::Testing::TimeHelpers`,
  now included globally in `test_helper.rb`) rather than mocking `Time`
  by hand -- including an integration test that actually POSTs a move
  after travelling past the time limit and confirms the server rejects
  it and finalizes the round itself.
- Rewrote `seeds.rb`, `demo:multiplayer`, and the multiplayer test suite
  again, this time around "simulate a round's worth of claims, then
  finalize" instead of "loop until a goal is hit" -- `GameCompletionService`
  itself never cared *why* a round was ending, so this was a smaller
  change than v5's rework.

## v5 — rotating targets + fixed "nothing happened" bug

Two real problems from playtesting:

1. **"The top selections need to flow and rotate out."** The target list
   was a fixed set generated once with the board -- once you claimed
   everything on it, the board was just... done, with no way to keep
   playing. Fixed by making every claim immediately replace itself with
   a freshly generated target on the same board, so the list never runs
   dry and always stays the same size.
2. **"I solved everything and nothing happened."** This was a real,
   separate bug: the "you're done!" banner only ever existed as
   server-rendered HTML baked in at page load. Since the game actually
   completes via an AJAX call (an auto-submit finishing the last claim),
   that static banner never had a chance to appear -- the grid just
   quietly locked itself with zero explanation. Fixed by having the
   client render its own completion banner the instant it detects the
   live transition to "completed," every time, regardless of how the
   game got there.

Since targets now rotate forever, "claim every target on the list" no
longer makes sense as a win condition -- replaced with a **claim goal**
per difficulty (Beginner: first to 8 claims, Intermediate: 10, Advanced:
12, Expert: 15). Solo games finish at their own goal; multiplayer games
finish the instant either player reaches it.

- **`GameSession#active_targets`** (new column) is now the live,
  constant-size target list actually shown to players. **`claims`**
  becomes a running history of every claim ever made (for scoring),
  decoupled from "which of the original targets are done."
- **`PuzzleGenerator.add_target`** generates one new target chain on an
  already-built grid without touching any existing cell values --
  reuses the exact same chain-length/multiply/value rules as the
  puzzle's difficulty, and tries to avoid repeating a value that's
  already showing elsewhere on the current list.
- **`GameSession#goal_reached?`** replaces the old `all_targets_claimed?`.
  **`GameSession#next_target_id`** hands out stable, never-reused ids as
  targets rotate through a session.
- New `GameSession#initialize_rotation!` callback auto-seeds
  `active_targets`/`claim_goal` from the puzzle the moment any
  controller creates a session -- no per-controller setup code to
  remember.
- **Progress indicator** ("6 / 8 claimed" + a fill bar) added to the
  board so the claim goal is visible while playing.
- **Target pop-in animation**: a freshly rotated-in target gets a
  spring-eased "pop in" (`target-pop-in` keyframes) so the flow reads as
  continuous rather than a silent swap. The old "claimed" strikethrough
  styling is gone since claimed targets no longer sit around marked --
  they're just gone, replaced.
- Rewrote `seeds.rb`, `demo:multiplayer`, and the multiplayer test suite
  around the new claim-goal loop instead of "solve the fixed list once."
  Added dedicated test coverage for rotation itself (`GameSession`
  model tests, `PuzzleGenerator.add_target` tests) and hardened the
  concurrency race test to also verify rotation happens correctly under
  real thread contention.

## v4 — real difficulty levels

The "still not balanced enough" feedback on v3 pointed at a real gap:
`difficulty` existed as a column and a form param, but nothing in
`PuzzleGenerator` actually used it — every board was generated with the
same fixed chain-length range, multiply odds, and value ceiling
regardless of what was passed in. This version makes difficulty
actually mean something.

- **Four real difficulty tiers**, each controlling grid size, chain
  length range, multiply odds, and value ceiling together (not
  independently), so easier tiers are easier to *visually solve*, not
  just smaller:
  - **Beginner** — 4×4 grid, chains always exactly 2 cells, addition
    only (multiply probability 0), target values capped at 20. Solving
    is just "spot two neighbors that add up to the number below."
  - **Intermediate** — 5×5 grid, 2-3 cell chains, some multiplication,
    values up to 50.
  - **Advanced** — 6×6 grid, 2-4 cell chains, values up to 150.
  - **Expert** — 8×8 grid, 2-4 cell chains, values up to 500 (this is
    the original v1/v2 default board, now just one tier among four
    instead of the only option).
- **Difficulty picker UI** on both the solo "new game" screen and the
  multiplayer "host a game" form — a row of selectable cards showing
  each tier's grid size, whether it uses multiplication, and its value
  range, so the choice is informed before you commit.
- **Difficulty is now visible everywhere a game is listed** — a small
  badge next to the game on the homepage dashboard, the multiplayer
  lobby's open-games list, "your games" list, and on the live game page
  header itself.
- **`Puzzle#difficulty` is now validated** against the real set of known
  levels (was previously an unconstrained free-text column that nothing
  checked). Added a follow-up migration to fix the column's stale
  `"normal"` default, which predates this system and was never a real
  difficulty option.
- Unknown/missing difficulty strings fall back to `beginner` (the new
  default) instead of erroring, matching "start beginner" as the
  natural on-ramp.
- New test coverage for the whole system: each tier's value ceiling and
  chain-length bounds are actually enforced, beginner is provably
  solvable with a 2-cell chain for every target, an unknown difficulty
  string falls back safely, and explicit `size:`/`target_count:`
  overrides still work for tests/tooling while chain complexity still
  comes from the difficulty preset. Also fixed one existing test
  (`target chain lengths are mixed`) that implicitly relied on the old
  always-2-to-4 range and would have silently broken under the new
  beginner-defaults-to-fixed-length-2 behavior.

## v3 — auto-submit + balanced randomization

- **Auto-submit on a correct link.** The moment a chain's running value
  matches a currently unclaimed target, it's claimed automatically — no
  more clicking a "Submit" button to cash in a winning chain. The button
  (relabeled "Check") still exists as a manual fallback for testing a
  chain that doesn't auto-match. The client mirrors the server's exact
  left-to-right evaluation so the auto-fire moment lines up with what the
  server will actually accept — the server still independently
  re-validates and re-evaluates every submission from scratch either way,
  so there's no new way to cheat via the client.
- **Guarded against rapid-click race conditions.** Since auto-submit
  fires far more often than the old manual flow, added a `submitting`
  flag so a click landing while a previous submission is still in flight
  (mid network round-trip) is ignored instead of corrupting the
  in-progress chain state.
- **Balanced "bag" randomization in `PuzzleGenerator`** (Tetris-piece
  style: shuffle a full set, hand pieces out one at a time, reshuffle a
  fresh set once empty), applied to two things:
  - **Digit bag**: every value 1-9 now shows up roughly evenly across
    the board instead of being independently random per cell, which
    could (rarely but really) clump — e.g. six 7s and zero 2s on a small
    board. Also increases the natural chance of multiple valid solving
    chains per target, since a more even digit spread means more
    coincidental combinations land on the same value.
  - **Chain-length bag**: target chains now draw a genuinely mixed
    spread of 2/3/4-cell lengths instead of leaving it to independent
    chance, so the target list feels more varied hand to hand.
- Added real test coverage for both bag guarantees
  (`puzzle_generator_test.rb`): digit spread bounds, chain-length
  variety, and determinism (same seed still produces the same board).

## v2 — smaller board, bigger feel

- **Grid shrunk from 8×8 to 5×5** (`GAME_GRID_SIZE` default), with target
  count trimmed from 8 to 6 to match. Fewer, bigger cells read much better
  at a glance — change either back via env vars if you want to experiment.
- **Numbers are now dramatically bigger** — `.cell-value` uses a responsive
  `clamp()` font size (roughly 1.6rem–2.6rem depending on screen width)
  instead of a fixed 1rem, and cells got a touch more padding/gap so the
  digits are the clear focal point of each tile.
- **Animated chain lines.** An SVG overlay draws a glowing line between
  each pair of linked cells as you build a chain — solid accent-blue for
  "+", dashed amber for "×" — so the expression you're building is visible
  on the board itself, not just in the text readout above it. Positioned
  with percentage math (not DOM measurement), so it stays correctly
  aligned at any screen size with zero layout-thrashing risk.
- **"Grabbed" pop animation.** The most recently clicked cell now pops
  with a spring-eased scale + glow burst (`grab-pop` keyframes) the
  instant it's added to the chain, so grabbing a number has a tactile,
  satisfying feel instead of just an instant color swap.
- **Claimed-target pop.** When a target chip flips from unclaimed to
  claimed, it does a quick rotate/scale "pop" (`claim-pop` keyframes) —
  fires for either player in multiplayer, not just the one who claimed it.
- **Synthesized sound effects (`app/javascript/sfx.js`).** Every sound is
  generated at runtime with the Web Audio API — no audio files to fetch,
  so this works fully offline and inside the Capacitor-wrapped mobile
  shell exactly like a browser:
  - rising blip on "+" links (pitch climbs slightly with chain length)
  - brighter two-tone chirp on "×" links, distinctly punchier than "+"
  - soft descending click when un-linking the last cell
  - four-note ascending chime when a chain claims a target
  - low buzz when a submitted chain doesn't match anything
  - a fuller fanfare once when a whole game completes
- **Deduped multiplayer feedback.** The player who submits a winning move
  gets instant sound/animation from their own request; the ActionCable
  broadcast that echoes back to them is now skipped so it doesn't
  double-fire the same claim sound and pop animation a second time.

## v1 — first working build

Initial MVP: solo + multiplayer grid-linking math game on Rails 7.1 +
Postgres, with real-time multiplayer via ActionCable and race-safe
target claiming via Postgres row locks.

Fixes applied after the first real run on a local machine (this list
exists so nobody re-introduces the same bugs later):

- **Pinned `minitest` to `~> 5.20`.** Rails 7.1's test runner
  (`line_filtering.rb`) was written against minitest 5.x's API and
  raises `ArgumentError: wrong number of arguments` under minitest 6.x,
  which bundler resolved to by default since nothing pinned it.
- **Removed `allow_browser versions: :modern`** from
  `ApplicationController`. Raised `NoMethodError` in this environment's
  resolved `actionpack` version; it was a nice-to-have UA filter, not
  load-bearing, so it was simplest to drop rather than chase down the
  exact version mismatch.
- **Fixed a shared-object race in the concurrency test.** The original
  `ClaimServiceConcurrencyTest` had both simulated player threads call
  `.with_lock` on the *same* in-memory `GameSession` Ruby object.
  Postgres row locking only works correctly when each thread/request
  holds its own object instance pointed at the same DB row — sharing
  one object raced at the Ruby level regardless of the DB lock. Real
  HTTP requests were never affected (`MovesController` already loads a
  fresh instance per request); only the test's own setup was wrong.
- **Fixed a false-failure in the same test caused by duplicate target
  values.** Puzzles can legitimately contain two *different* targets
  that happen to share the same displayed value (by design — see
  `PuzzleGenerator`). The test originally grabbed `targets.first`
  without checking uniqueness, so on some seeds both players correctly
  claimed two different same-valued targets — which looks like "the
  lock didn't work" but is actually correct game behavior. Fixed by
  selecting a target whose value is provably unique on that board
  before racing for it.
- **Fixed a Postgres integer overflow in `PuzzleGenerator`.**
  `Random.new_seed` (used whenever no explicit `seed:` is passed — i.e.
  every real "Play Solo" click) returns numbers far larger than a
  4-byte Postgres `integer` column can store, causing every solo game
  creation to 500. Replaced with `SecureRandom.random_number(2_147_483_647)`,
  which stays within the column's range. Added a regression test
  (`puzzle_generator_test.rb`) that calls `PuzzleGenerator.call` with no
  seed at all, the way real controllers do, so this can't silently come
  back.
