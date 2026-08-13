# Changelog

## v18 — explicit Winner/Opponent labeling in the All games feed

Previously showed both players' scores side by side ("p1 vs p2 · 250-100
pts"), requiring a mental comparison to figure out who actually won.

- **New `ApplicationHelper#multiplayer_result`** computes one of three
  states as plain data (never pre-built HTML, so the view's normal
  `<%= %>` interpolation keeps auto-escaping usernames): `:winner`
  (completed with a clear winner -- "Winner: **name** (X pts) ·
  Opponent: name (Y pts)", the winner's name highlighted in green),
  `:tie` (completed with no winner -- `GameSession#winner` already
  correctly returns nil for a tie rather than picking one arbitrarily),
  or `:in_progress` (not completed yet -- shows both current scores
  without claiming a premature winner).
- Verified the winner is reported identically regardless of which
  player is passed first/second -- who's "player one" in the
  participant list should never affect who's actually shown as the winner.
- New test coverage: all three states directly at the helper level, plus
  full end-to-end integration tests confirming the actual rendered
  homepage text and the `.winner-name` styling for each case -- winner,
  tie, and still-in-progress (which also fixed a now-stale existing
  test that expected the old dash-separated score format).

## v17 — leaderboard split into 4 difficulty-specific tables

A Beginner regular and an Expert grinder were never really comparable
on one combined ranking -- the leaderboard is now four separate tables,
one per difficulty, each ranked by total points within that difficulty.

- **New `UserDifficultyStat` model** (new migration) -- a per-user,
  per-difficulty version of the existing lifetime `UserStat`: games
  played/won, targets claimed, total points, best solo score, all
  scoped to one specific difficulty rather than a single blended total.
- **`UserDifficultyStat.record_completed_game!`** is the one place that
  rolls a finished game into these stats -- used by both
  `GameCompletionService` for every game completed from now on, AND by
  the migration itself to **backfill every already-completed game**
  in one step. Keeping this logic in exactly one method means the
  backfill and live gameplay can never drift out of sync with each
  other, and means the backfill is implicitly covered by the same
  tests that cover live play.
- **No `.limit()` on any leaderboard table, on purpose.** An earlier,
  unrelated feature on this app (the homepage's game history) caused
  real, confusing user-facing bugs from a silent 5-item cap. Learned
  that lesson -- every leaderboard shows everyone within that
  difficulty, contained in the same scrollable panel pattern
  (`.game-list-scroll`) already used elsewhere, not an arbitrary cutoff.
- Ranked by **total points** within each difficulty (primary), games
  won (tiebreak) -- consistent with points being the app's actual
  scoring metric since the value-tiered system.
- New test coverage: stats accumulate correctly across multiple games
  at the same difficulty, games at different difficulties never mix
  into the same row, multiplayer win-crediting only goes to the actual
  winner (never on a tie), `GameCompletionService` wires this in
  automatically with no manual step, and at the controller level --
  all four difficulty sections render, a Beginner-only player never
  leaks onto the Expert table, ranking is correctly points-first, and
  an empty difficulty shows a friendly message rather than a blank or
  broken section.

## v16 — mobile-friendly nav + broader responsive polish

- **Hamburger menu for the top nav**, both the main site header and the
  admin layout. Collapses below 720px viewport width into a standard
  three-line toggle that expands a vertical dropdown panel; stays a
  normal horizontal row above that width. New `nav_controller.js`
  (Stimulus) handles the show/hide -- deliberately simple, no
  outside-click or navigation-based auto-close logic, since clicking
  any link in the open menu already navigates away, which tears down
  and recreates the controller for free (resetting it closed).
- **Fixed a real gap while in there**: the admin layout never loaded
  any JavaScript at all (`javascript_importmap_tags` was missing
  entirely) -- meaning even after building the hamburger markup, it
  would have rendered but done nothing when clicked on admin pages.
  Added it.
- **Broader responsive audit pass**: added `flex-wrap` to four more
  flex rows that could still cramp on a narrow phone screen without it
  -- the homepage's hero action buttons, the in-game timer/claims
  readout, and the end-of-round stats modal's stat list and action
  buttons. Most of the app already had this from earlier overflow
  fixes (game lists, the difficulty picker, admin tables); this closes
  out the remaining gaps found by an explicit pass rather than waiting
  for another bug report.
- New test coverage: the hamburger button and its Stimulus wiring
  (`data-controller`, `data-action`, `data-nav-target`) are present on
  both the main site and admin layouts, and a dedicated regression test
  confirms the admin layout actually loads JavaScript now (asserting on
  the literal absence of that bug going forward, not just the visible
  markup).

## v15.2 — hide "Continue with Facebook" from the public until App Review is done

Facebook sign-in works correctly (verified for the app owner and any
Business Manager tester), but the app isn't through Meta's Business/App
Review yet -- meaning any visitor who ISN'T a tester and clicks the
button hits a dead-end error straight from Facebook. That's a confusing
experience for a random visitor and easily reads as "this app is
broken" rather than a Facebook permissions issue.

- **New `FACEBOOK_LOGIN_PUBLIC` env var** (default `false`/hidden).
  Controls only the button's *visibility* on the login/signup pages --
  the credentials themselves stay fully configured and working either
  way, so testers can still use it directly. Reads live via `ENV` at
  render time (not baked into boot-time config), so it's a one-line
  env var flip + restart to turn back on, no code changes.
- Google's button always shows regardless -- it's fully live for
  anyone since publishing that consent screen didn't require the same
  Business Verification friction Facebook's did.
- `OAUTH.md` updated with what was actually learned trying to get
  Facebook out of Development mode: Meta's Business Verification
  requires real legal business documents, and the "simpler,
  ID-only Individual verification" path documented for solo developers
  did not actually appear as an option in practice for this account --
  worth knowing before investing more time there without a registered
  business entity.
- New test coverage: the Facebook button is hidden by default on both
  login and signup, Google's is always present, and the button
  correctly reappears on both pages once the env var is explicitly set.

## v15.1 — sign-in method visible in the admin panel

- **New `oauth_provider_badge(user)` admin helper**, showing a small
  colored badge — **Google**, **Facebook**, or **Password** — wherever
  a user shows up in the admin panel: the users index, the user detail
  page header, and the dashboard's "Recent signups" table. No more
  dropping into the Rails console to check whether an account is
  OAuth-linked.
- New test coverage confirming the correct badge renders for both an
  OAuth account and a traditional one, on both the index and detail pages.

## v15 — sign in with Google / Facebook

New gem dependencies this time (`omniauth`, `omniauth-google-oauth2`,
`omniauth-facebook`, `omniauth-rails_csrf_protection`) -- can't verify
these resolve cleanly against Rails 7.1.6 without running bundler
myself, same caveat as always. Much narrower dependency footprint than
something like the ActiveAdmin gem would have been, but still real risk
worth naming.

- **"Continue with Google" / "Continue with Facebook" buttons** on both
  the login and signup pages (shared partial, `shared/_oauth_buttons`).
  Buttons are `button_to` (POST), not plain links, and marked
  `data-turbo: false` -- both required for the OAuth redirect chain to
  work correctly (CSRF protection needs POST for the request phase;
  Turbo's fetch-based navigation would break the full-page redirect to
  Google/Facebook otherwise).
- **New `provider`/`uid` columns on `users`**, plus `password_digest`
  relaxed from `NOT NULL` -- OAuth-only accounts never set a password.
  `has_secure_password validations: false` disables its built-in
  presence check accordingly; a new context-scoped validation
  (`on: :signup, if: -> { provider.blank? }`) requires a password only
  for traditional signups. Password-confirmation matching, which
  `has_secure_password`'s disabled validations also would have covered,
  is reimplemented explicitly (`validates :password, confirmation: true`)
  so that didn't silently regress.
- **`User.from_omniauth(auth)`**: finds an already-linked account by
  provider+uid, or links a new OAuth identity to an existing account
  with a matching email (someone who signed up traditionally before,
  now trying Google) rather than creating a duplicate. Returns `nil`
  for a genuinely new sign-in.
- **Username-completion step for brand-new sign-ins.** This app's whole
  design keeps the username as the only thing ever shown to other
  players (see `User#name`) -- can't skip that just because OAuth
  handed us a real name and email. A new sign-in lands on a one-field
  form (`OmniauthRegistrationsController`) pre-filled with the
  provider's real name/email (stashed server-side in
  `session[:pending_oauth]`, never trusted from a hidden form field),
  asking only for a username before the account actually gets created.
- **`OAUTH.md`**: the external setup walkthrough for both providers --
  Google Cloud Console and Meta for Developers, including the two
  redirect URIs each provider needs (`localhost` + `orbit-math.us`),
  and an honest heads-up that Facebook's path to public (non-Development-mode)
  access typically needs Meta's App Review, which Google's equivalent
  doesn't.
- Real test coverage: `User.from_omniauth`'s three branches (linked
  account, email-linking, brand new) plus the "no email" edge case;
  password validation correctly required/skipped based on OAuth status;
  password-confirmation mismatch still caught after disabling
  `has_secure_password`'s own checks; `uid` uniqueness correctly scoped
  per-provider, not global; the full callback flow end-to-end via
  OmniAuth's test mode (existing linked user logs in directly, matching
  email links rather than duplicates, brand new redirects to the
  username step with zero account created yet); and the username step
  itself (pre-fill correctness, successful completion, validation
  errors, duplicate username rejection) -- 20+ new test cases in total
  across three new test files.

## v14.6 — "All games": actually site-wide this time

v14.5's "show every game" was still wrong -- it removed the 5-game cap
but kept the list scoped to `current_user.game_sessions`, i.e. only the
viewer's own games. What was actually wanted: every game played by
anyone, visible to any logged-in viewer, since the section is really a
site-wide activity feed, not personal history.

- **`@all_games` is now `GameSession.all`** (eager-loaded, ordered by
  recency), not scoped to the current user at all. Renamed the section
  "All games" accordingly.
- **Rows no longer assume the viewer is a participant.** Multiplayer
  rows show both real players and their points (`p1 vs p2 · 250-100 pts`);
  solo rows show whoever actually played it. Previously the row
  template assumed `current_user` was always one of the two players,
  which no longer holds now that everyone sees everyone's games.
- **"Open" now only shows if the viewer is genuinely a participant** in
  that specific game and it isn't completed -- important now that the
  list includes games the viewer had nothing to do with; showing an
  "Open" link into someone else's private game would have just sent
  them into an authorization redirect.
- Checked participancy via the already-eager-loaded `participants`
  collection (`g.participants.any? { |p| p.user_id == current_user.id }`)
  rather than the separate `users` through-association, avoiding an
  extra query per row that a naive `g.users.include?(...)` would have
  triggered.
- Rewrote all four related tests around the corrected behavior,
  including one that specifically logs in as a third party who played
  none of the eight seeded games and confirms all eight still show up
  -- the exact scenario that was still broken in v14.5.

## v14.5 — game history shows every game, not just the last 5

The actual bug behind "my friend's games aren't showing up": `@recent_games`
was capped at `.limit(5)`, silently hiding anything past a player's 5
most recent games. Not related to the scoring-version change at all --
old games were always still there, just hidden past the cutoff.

- Removed the limit entirely -- shows full game history now. The
  existing `.game-list-scroll` container (added in v14.4, contained
  scroll) already handles a long list without breaking page layout, so
  this didn't need pagination to be usable.
- Renamed the section from "Recent games" to **"Game history"**, since
  the old name was part of what caused the confusion -- "recent"
  implied a deliberately limited slice, which is exactly what it was,
  silently.
- New regression test: a player with 7 completed games sees all 7 in
  their history, not 5.

Worth knowing: if this list grows large for a very active player,
real pagination is the next step -- "show everything" was the
explicit, deliberate choice for now, not a permanent architecture decision.

## v14.4 — actually fixed the homepage's Open multiplayer games overflow

v14.3's `.game-list` flex-wrap fix was aimed at the wrong root cause.
The real problem: "Open multiplayer games" and "Recent games" sit in a
3-column dashboard grid, squeezing each card to roughly a third of the
page width (~300px) -- genuinely too narrow for a row like "hosted by
username · code ABCDEF · [badge] [Join button]" to fit comfortably no
matter how it wraps.

- **`.card-wide`**: both cards now span the full width of the dashboard
  row instead of competing for a third of it alongside "Your stats" --
  this is the actual "widen it" fix.
- **`.game-list-scroll`**: a contained scroll area (max-height 320px,
  scrolls both directions) wrapping each list, as a fallback for a
  long username or many open games even at full card width -- the
  "horizontal and vertical scroll bar" half of the original suggestion,
  which v14.3 hadn't actually added anywhere on the homepage.

## v14.3 — Recent games shows the actual player, admin tables get proper scroll

- **Recent games now explicitly shows the player's own username**, not
  just the opponent for multiplayer or nothing at all for solo. Reads
  as "yourname vs opponentname · Beginner · 150 pts" or "yourname ·
  Solo run · Beginner · 100 pts" now.
- **Admin tables now scroll both directions, contained.** `.admin-main`
  widened from 960px (inherited from the normal site width) to 1400px
  -- admin tables have a lot more columns than anything else in the app
  and were forced into horizontal scroll far more often than necessary.
  `.admin-table-wrap` now caps height at `70vh` with its own vertical
  scroll (previously the whole page just grew indefinitely for a
  200-row table) and keeps horizontal scroll for narrow viewports. The
  header row is now `position: sticky` within that scroll area, so
  column labels stay visible while scrolling a long table instead of
  scrolling out of view immediately.
- Also hardened `.game-list` (used by the homepage's Recent
  games/Open games and the multiplayer lobby) against the same class of
  overflow: rows now wrap (`flex-wrap: wrap`) instead of forcing
  horizontal scroll when a row's content (username + difficulty badge +
  points + Open link) doesn't fit on one line on a narrow screen.
- New/updated test coverage: both the player's and opponent's usernames
  are asserted present for multiplayer, and a dedicated test confirms
  the player's username shows for solo runs too (previously untested,
  and the exact gap that let the missing-username issue slip through).

## v14.2 — Recent games shows who/points/difficulty, no more opening finished games

- **"Recent games" now shows the opponent's username** (multiplayer) or
  "Solo run", the **difficulty badge**, and **points earned** -- replaces
  the old raw `mode · status` line, which told you nothing useful at a
  glance.
- **Removed the "Open" link for completed games.** There was never a
  real reason to reopen a finished round -- rounds are short (60-150s)
  and always resolve via the timer, so in practice every entry in this
  list was already done. The link now only appears for a game that's
  genuinely still in progress (an edge case, e.g. a multiplayer game
  stuck waiting on an opponent), not the common case.
- Fixed a latent N+1 query risk while in there: `HomeController` now
  eager-loads `puzzle` and `participants: :user` for recent games (and
  `puzzle`/`host` for open games), so rendering the list doesn't fire a
  fresh query per game for difficulty labels and opponent lookups.
- New test coverage: the opponent's username, points, and difficulty
  actually render correctly for a real claimed game, and a completed
  game has no Open link while an in-progress one still does.

## v14.1 — live expression shows the running total, not just the popup

The live equation display (above the grid, while building a chain) only
ever showed the running math itself -- "6 x 7" -- never the computed
total until after claiming, when the floating popup would show it. Now
it shows the full equation live: "6 x 7 = 42", "1 x 3 + 8 = 24", etc.,
the moment there's at least one link to actually compute. Reuses the
same `currentChainValue()` the auto-submit match-check already relies
on, so there's no new logic, just a new place it's also displayed.

## v14 — grey meteors, value-tiered points, no more Submit/Clear buttons

- **Meteors are now grey**, not blue-purple. New `--meteor-base/-light/-dark`
  CSS variables dedicated to the grid (kept separate from `--bg-cell`,
  which is still used elsewhere, so this doesn't ripple into other UI).
  Crater contrast bumped up slightly since it needed to read clearly
  against the lighter grey base.
- **Real point-based scoring, corrected from an earlier wrong guess.**
  First pass made points a flat rate per *difficulty* (Beginner 100,
  Expert 1000) -- wrong. The actual request: points scale with the
  *value of the specific target solved*, within any difficulty. Fixed
  properly: `ClaimService.points_for_value(value)` now maps a target's
  value to points via the same five tiers the material styling already
  uses -- **Crystal (1-10) = 25pts, Gold (11-20) = 50pts, Emerald
  (21-50) = 100pts, Platinum (51-150) = 250pts, Diamond (151+) =
  500pts**. Points and visual rarity are now guaranteed to agree,
  since they share one breakpoint list, tested directly (every
  boundary value, not just one per tier).
- **`GameSession#score_for` split into two clearly-named methods**:
  `targets_claimed_by(user)` (raw count, for lifetime "targets claimed"
  stats) and `points_for(user)` (the real scoring/win-determining
  metric). `winner` now ranks by points. Every call site across the
  app -- `GameCompletionService`, `GameStatePresenter`, both admin
  views, both completion banners, seeds, the demo rake task -- updated
  and swept for zero stale references.
- **Removed the Submit/Clear buttons.** Auto-submit has handled every
  case that matters since several versions back (a chain claims the
  instant it matches, automatically); the buttons had no unique
  capability left to justify keeping. Undo-one-step-at-a-time (click
  the last cell again) still works without a dedicated Clear button.
- **Live points total next to the equation**, as requested -- shows the
  current player's running point total for the round, updating in real
  time, positioned directly beside the expression readout.
- New test coverage: every tier boundary value maps to the correct
  points, a real claim stores the correct tiered (not flat) points on
  its record, and a full round on Expert difficulty (widest value
  range) confirms claimed points always land on one of the five real
  tier values and match what the target's own value implies.

## v13 — circular cratered asteroids + material tiers for targets

- **Cells are now genuinely circular**, not the irregular blob shapes
  from before. Craters are simulated with layered `radial-gradient`
  "dents" (a highlight for the lit side, 3 darker dents at varying
  positions/sizes) plus an inset box-shadow for subtle spherical
  shading -- still no images, pure CSS. The five `data-shape` variants
  (already assigned deterministically by grid position in
  `grid_controller.js`) now vary crater *positions* instead of the
  outer silhouette, so neighboring asteroids still read as distinct
  despite all being circles.
- **Target chips are now styled by material tier**, escalating with
  value: **Crystal** (1-10, cyan gem), **Gold bar** (11-20), **Emerald**
  (21-50, green gem), **Platinum** (51-150), **Diamond** (151+, glowing
  white/rainbow gem). Tiers are computed client-side from the target's
  value (`grid_controller.js#materialTierClass`) and applied as a CSS
  class alongside the existing pop-in animation. Ranges are chosen to
  span every difficulty's ceiling -- Beginner (max 20) only ever shows
  crystals and gold, Expert (max 500) can show the full set -- so
  harder difficulties naturally reveal rarer-looking loot, reinforcing
  the difficulty curve visually, not just numerically.
- The homepage's "How to Play" demo board picks up the new circular
  cell styling automatically, since it reuses the same `.cell`/
  `data-shape` markup as the real game -- no separate update needed there.

## v12.1 — concurrency test fix

Fixed `ClaimServiceConcurrencyTest` to check the right invariant: that
the *specific* target being raced for can only be won once, rather than
"only one success total" -- the latter could false-fail whenever the
replacement target that rotates in after a win coincidentally shares
the same value as what was just claimed, which is legitimate game
behavior (duplicate target values are allowed by design), not a bug.

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
