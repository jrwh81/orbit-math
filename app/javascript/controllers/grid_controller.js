import { Controller } from "@hotwired/stimulus"
import { playAdd, playMultiply, playRemove, playClaim, playFail, playVictory, playReward } from "sfx"
import { spawnPixiShatter } from "pixi_shatter"

// Click a neighboring cell to link it with "+". Double-click a neighboring
// cell (second click within DOUBLE_CLICK_MS) to link it with "*" instead.
// Clicking the last cell in the chain again removes it. Orthogonal AND
// diagonal neighbors both count -- see renderGrid/chooseCell -- a
// diagonal link shows up as one arm of the criss-cross mark at the
// shared corner of that 2x2 box lighting up. All evaluation shown here
// is a preview only -- the server re-validates and re-evaluates every
// submission from scratch.
const DOUBLE_CLICK_MS = 320

// How long the end-of-round stats screen stays up before automatically
// sending the player home. "Play again" / "Continue" both skip the wait.
const AUTO_HOME_DELAY_MS = 6000

// How long a claimed cell stays hidden (see .cell.exploding in the
// stylesheet) before fading in to reveal its new number -- tuned to
// roughly match the shatter effect's own duration, whichever version
// (PixiJS or the CSS fallback) actually played, so the new number
// doesn't pop in while debris is still visibly mid-flight over it.
const EXPLOSION_REVEAL_DELAY_MS = 650

// Grid cell values are always a single digit 1-9 (see PuzzleGenerator's
// digit-bag randomization), so three even bands cover the whole range.
// Only applied once a cell is actually part of the current chain (see
// renderGrid) -- idle cells stay a neutral off-white so color reads as
// "this is in your solution," not just decoration. Colors (see
// application.css) are deliberately NOT a red/green pairing -- that's
// the axis most common colorblindness struggles with.
function cellValueColorClass(value) {
  if (value <= 3) return "cell-value-low"
  if (value <= 6) return "cell-value-mid"
  return "cell-value-high"
}

// How much space (in fr units) each connector gutter takes relative to
// a cell's own "1fr" track. Small enough that cells still dominate the
// board, big enough for a legible +/x glyph. Used for both rows and
// columns, and the grid-rows container is forced to aspect-ratio:1, so
// cells come out square regardless of how many there are.
const CONNECTOR_FR = 0.22

// Builds the grid-template-columns/rows value for an NxN board: cell,
// connector, cell, connector, ... cell. Same string works for both axes
// since the connector gutter is symmetric.
function gridTemplateTracks(size) {
  const parts = []
  for (let i = 0; i < size; i++) {
    parts.push("1fr")
    if (i < size - 1) parts.push(`minmax(6px, ${CONNECTOR_FR}fr)`)
  }
  return parts.join(" ")
}

// Colors for the CSS-fallback spark burst (see application.css's
// --spark-a/-b/-c) -- glowing chips in the game's own accent palette,
// replacing the old grey meteor-chunk look now that cells aren't rocks.
const SPARK_COLORS = ["var(--spark-a)", "var(--spark-b)", "var(--spark-c)"]

// Undirected key for a pair of orthogonally-adjacent cells, order
// independent, so a connector can look itself up regardless of which
// direction the chain happened to walk through it.
function connectorKey(a, b) {
  const pair = [`${a.row},${a.col}`, `${b.row},${b.col}`].sort()
  return pair.join("|")
}

// Maps every "connector between step i and step i+1" in the current
// chain to the op that links them, so renderGrid can look up whether a
// given gutter between two specific cells should show +/x instead of
// its default dash.
function buildChainConnectorMap(path, ops) {
  const map = new Map()
  for (let i = 0; i < path.length - 1; i++) {
    map.set(connectorKey(path[i], path[i + 1]), ops[i])
  }
  return map
}

export default class extends Controller {
  static targets = ["grid", "targets", "scoreboard", "timer", "expression", "pointsTotal", "message", "completion", "popupLayer",
    "claimNameInput", "claimEmailInput", "claimNameError"]
  static values = {
    submitUrl: String,
    finishUrl: String,
    newGameUrl: String,
    homeUrl: String,
    currentUserId: Number,
    state: Object,
    isGuest: Boolean,
    nameClaimed: Boolean,
    claimNameUrl: String
  }

  connect() {
    this.path = []
    this.ops = []
    this.pendingTimer = null
    this.pendingCell = null
    this.submitting = false
    this.finishing = false
    this.tickInterval = null

    // Tracks which target ids were visible last render, so a freshly
    // rotated-in target (an id we've never seen before) gets a "pop in"
    // animation instead of appearing silently. Seeded from the initial
    // state so page load never fires a false "just arrived" animation.
    this.previousTargetIds = new Set((this.stateValue.targets || []).map((t) => t.id))
    this.justArrivedIds = []
    // Same idea, but for individual grid cells: a claimed chain's cells
    // get new digit values, and this lets renderGrid() give exactly
    // those cells a "just refreshed" flip animation.
    this.justRefreshedCells = []
    this.wasCompleted = this.stateValue.status === "completed"
    this.remainingSeconds = this.stateValue.time_remaining_seconds ?? this.stateValue.time_limit_seconds ?? 0

    this.render()
    this.startTicking()

    this.remoteUpdateHandler = (event) => this.applyIncomingState(event.detail)
    this.element.addEventListener("grid:remote-update", this.remoteUpdateHandler)
  }

  disconnect() {
    this.element.removeEventListener("grid:remote-update", this.remoteUpdateHandler)
    if (this.pendingTimer) clearTimeout(this.pendingTimer)
    this.stopTicking()
  }

  // Swaps in a fresh game state (from either our own fetch response or an
  // opponent's move arriving over ActionCable), figuring out what's worth
  // celebrating before the old state is gone.
  applyIncomingState(newState) {
    const newIds = (newState.targets || []).map((t) => t.id)
    this.justArrivedIds = newIds.filter((id) => !this.previousTargetIds.has(id))
    this.previousTargetIds = new Set(newIds)

    this.justRefreshedCells = this.diffGridCells(this.stateValue.grid, newState.grid)

    const justCompleted = newState.status === "completed" && !this.wasCompleted
    this.wasCompleted = newState.status === "completed"

    this.stateValue = newState
    // Re-sync the local countdown to the server's authoritative value
    // every time fresh state arrives, so client/server clock drift
    // never accumulates across a long round.
    this.remainingSeconds = newState.time_remaining_seconds ?? this.remainingSeconds

    this.spawnShatterForCells(this.justRefreshedCells)
    this.render()

    if (justCompleted) {
      this.stopTicking()
      this.celebrateCompletion()
    } else {
      this.startTicking()
    }
  }

  // Compares old vs new grid cell-by-cell, returning "row,col" keys for
  // every cell whose value changed -- used to give exactly those cells a
  // "just refreshed" flip animation instead of every cell flickering.
  diffGridCells(oldGrid, newGrid) {
    if (!oldGrid || !newGrid) return []

    const changed = []
    for (let r = 0; r < newGrid.length; r++) {
      for (let c = 0; c < newGrid[r].length; c++) {
        if (oldGrid[r]?.[c] !== newGrid[r][c]) changed.push(`${r},${c}`)
      }
    }
    return changed
  }

  // ------------------------------------------------------------- timer

  startTicking() {
    this.stopTicking()
    if (this.stateValue.status !== "active") return

    this.tickInterval = setInterval(() => this.tick(), 1000)
  }

  stopTicking() {
    if (this.tickInterval) clearInterval(this.tickInterval)
    this.tickInterval = null
  }

  tick() {
    if (this.stateValue.status !== "active") {
      this.stopTicking()
      return
    }

    this.remainingSeconds = Math.max(0, this.remainingSeconds - 1)
    this.renderTimer()

    if (this.remainingSeconds <= 0) {
      this.stopTicking()
      this.finishGame()
    }
  }

  // Called the instant this client's own countdown hits zero. The server
  // is the source of truth either way -- MovesController independently
  // refuses to process any move once time is actually up server-side,
  // so a client whose clock runs slightly fast can't cheat itself extra
  // time, and a client whose clock runs slightly slow just gets told
  // the round already ended.
  async finishGame() {
    if (this.finishing) return
    this.finishing = true

    try {
      const response = await fetch(this.finishUrlValue, {
        method: "POST",
        headers: { "X-CSRF-Token": this.csrfToken(), Accept: "application/json" }
      })
      const data = await response.json()
      this.applyIncomingState(data)
    } catch (e) {
      // best effort -- if this fails, the next move attempt (solo) or
      // the opponent's own timer (multiplayer) will still catch it
    } finally {
      this.finishing = false
    }
  }

  // This is the fix for "I solved everything and nothing happened": the
  // game completing mid-play (via an auto-submit AJAX call) used to have
  // NO visual feedback at all beyond the grid quietly disabling itself --
  // there was no static server-rendered banner because completion never
  // triggered a full page reload. Now the client renders its own banner
  // the instant it detects the transition to "completed", every time.
  //
  // Shows a full-screen stats modal (result headline + this player's
  // round highlights: claims, longest chain, highest value claimed),
  // then automatically returns to the homepage -- where UserStat is
  // already updated by the time they land there, since
  // GameCompletionService runs server-side before this response ever
  // reaches the client -- after a short delay. "Play again" / "Continue"
  // both skip the wait for anyone who doesn't want to sit through it.
  celebrateCompletion() {
    playVictory()

    const players = this.stateValue.players || []
    const mine = (this.stateValue.summary || {})[this.currentUserIdValue] || {
      points: 0,
      claims: this.stateValue.claims_count || 0,
      longest_chain: 0,
      highest_value: 0
    }

    let headline
    if (players.length >= 2) {
      const [p1, p2] = players
      const winnerId = this.stateValue.winner_id
      if (winnerId) {
        const winnerName = players.find((p) => p.user_id === winnerId)?.name || "Someone"
        const iWon = winnerId === this.currentUserIdValue
        headline = iWon
          ? `Time's up -- you win! ${p1.points} - ${p2.points}`
          : `Time's up -- ${winnerName} wins. ${p1.points} - ${p2.points}`
      } else {
        headline = `Time's up -- it's a tie! ${p1.points} - ${p2.points}`
      }
    } else {
      headline = "Time's up!"
    }

    // Guests (see GuestPlayController) start with an auto-generated
    // placeholder name -- the first time one of them finishes a round,
    // this offers the real name/email prompt right in the same modal
    // instead of a separate page, so there's zero friction before the
    // FIRST game and exactly one friendly ask right after it.
    const showClaimName = this.isGuestValue && !this.nameClaimedValue

    this.completionTarget.innerHTML = `
      <div class="stats-overlay">
        <div class="stats-modal">
          <h2>${headline}</h2>
          <ul class="stats-list">
            <li><span class="stats-value">${mine.points}</span><span class="stats-label">points earned</span></li>
            <li><span class="stats-value">${mine.claims}</span><span class="stats-label">prizes won</span></li>
            <li><span class="stats-value">${mine.longest_chain}</span><span class="stats-label">longest chain</span></li>
            <li><span class="stats-value">${mine.highest_value}</span><span class="stats-label">highest prize claimed</span></li>
          </ul>
          ${showClaimName ? this.claimNameBlockHtml() : this.finalActionsHtml()}
        </div>
      </div>
    `

    // Auto-home is skipped while the claim-name prompt is showing --
    // yanking someone to the homepage while they're mid-typing their
    // name would be a bad time. It resumes being a normal manual
    // Play again/Continue choice once they submit or skip (see
    // replaceClaimNameBlockWithActions), just without the countdown.
    if (!showClaimName) {
      setTimeout(() => {
        window.location.href = this.homeUrlValue
      }, AUTO_HOME_DELAY_MS)
    }
  }

  claimNameBlockHtml() {
    const currentName = this.stateValue.players?.find((p) => p.user_id === this.currentUserIdValue)?.name || ""
    return `
      <div class="claim-name-block">
        <p class="claim-name-prompt">Nice round! Put your name on the leaderboard?</p>
        <p class="claim-name-error" data-grid-target="claimNameError"></p>
        <input type="text" class="claim-name-input" data-grid-target="claimNameInput" placeholder="Your name" value="${currentName}" maxlength="20">
        <input type="email" class="claim-name-input" data-grid-target="claimEmailInput" placeholder="Email (optional)">
        <div class="stats-actions">
          <button type="button" class="btn btn-secondary" data-action="grid#skipClaimName">Skip</button>
          <button type="button" class="btn btn-primary" data-action="grid#submitClaimName">Save to leaderboard</button>
        </div>
      </div>
    `
  }

  finalActionsHtml() {
    return `
      <div class="stats-actions">
        <a href="${this.newGameUrlValue}" class="btn btn-secondary">Play again</a>
        <a href="${this.homeUrlValue}" class="btn btn-primary">Continue</a>
      </div>
      <p class="stats-auto-note">Heading back to home&hellip;</p>
    `
  }

  // Name has to be unique -- same validation the model already enforces
  // for every account -- so a collision here is a normal, expected
  // outcome, not an error state; just surface it and let them try again.
  async submitClaimName() {
    const username = this.claimNameInputTarget.value.trim()
    const email = this.hasClaimEmailInputTarget ? this.claimEmailInputTarget.value.trim() : ""

    if (!username) {
      this.claimNameErrorTarget.textContent = "Enter a name first."
      return
    }

    let data
    try {
      const response = await fetch(this.claimNameUrlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": this.csrfToken(),
          Accept: "application/json"
        },
        body: `username=${encodeURIComponent(username)}&email=${encodeURIComponent(email)}`
      })
      data = await response.json()
    } catch (e) {
      this.claimNameErrorTarget.textContent = "Connection error, try again."
      return
    }

    if (data.success) {
      this.replaceClaimNameBlockWithActions(`You're on the board as ${data.username}!`)
    } else {
      this.claimNameErrorTarget.textContent = (data.errors && data.errors[0]) || "Couldn't save that name."
    }
  }

  skipClaimName() {
    this.replaceClaimNameBlockWithActions()
  }

  replaceClaimNameBlockWithActions(note) {
    const block = this.completionTarget.querySelector(".claim-name-block")
    if (!block) return

    block.outerHTML = this.finalActionsHtml()

    if (note) {
      const modal = this.completionTarget.querySelector(".stats-modal")
      const noteEl = document.createElement("p")
      noteEl.className = "claim-name-success"
      noteEl.textContent = note
      const actions = modal.querySelector(".stats-actions")
      modal.insertBefore(noteEl, actions)
    }
  }

  // ---------------------------------------------------------------- render

  render() {
    this.renderGrid()
    this.renderTargets()
    this.renderScoreboard()
    this.renderTimer()
    this.renderExpression()
    this.renderPointsTotal()
  }

  // Cells sit on the odd grid lines, a thin dash/plus/times gutter sits
  // between every orthogonally-adjacent pair, and each interior corner
  // (where four cells meet) gets a criss-cross diagonal indicator --
  // two overlapping "\" and "/" marks that approximate an X at rest.
  // Linking a cell to its diagonal neighbor lights up just that one
  // arm into a "+"/"x", while the other diagonal's mark stays dim, so
  // it reads as "one arm of the X turned into the operator you used."
  renderGrid() {
    const grid = this.stateValue.grid
    const size = grid.length
    const gameOver = this.stateValue.status === "completed"
    const connectorMap = buildChainConnectorMap(this.path, this.ops)

    let cellsHtml = ""
    grid.forEach((row, r) => {
      row.forEach((value, c) => {
        const stepIndex = this.path.findIndex((p) => p.row === r && p.col === c)
        const isNewest = stepIndex !== -1 && stepIndex === this.path.length - 1
        const classes = ["cell"]
        if (stepIndex !== -1) classes.push("selected")
        if (isNewest) classes.push("just-grabbed")
        if (gameOver) classes.push("disabled")
        if (this.justRefreshedCells.includes(`${r},${c}`)) classes.push("exploding")

        const gridRow = 2 * r + 1
        const gridCol = 2 * c + 1

        const isSelected = stepIndex !== -1
        const valueClass = isSelected ? cellValueColorClass(value) : "cell-value-neutral"

        cellsHtml += `<button type="button" class="${classes.join(" ")}" style="grid-row:${gridRow};grid-column:${gridCol};" data-row="${r}" data-col="${c}" data-action="click->grid#cellClicked">
          <span class="cell-value ${valueClass}">${value}</span>
          ${stepIndex !== -1 ? `<span class="cell-order">${stepIndex + 1}</span>` : ""}
        </button>`

        if (c < size - 1) {
          cellsHtml += this.renderConnector(r, c, r, c + 1, gridRow, gridCol + 1, "connector-horizontal", connectorMap)
        }
        if (r < size - 1) {
          cellsHtml += this.renderConnector(r, c, r + 1, c, gridRow + 1, gridCol, "connector-vertical", connectorMap)
        }
        // The criss-cross: only exists where a full 2x2 box of cells
        // does (this one plus its right/below/diagonal neighbors), and
        // sits on the corner intersection those four cells share. Two
        // independent marks, one per diagonal, stacked at that same
        // grid position.
        if (r < size - 1 && c < size - 1) {
          const cornerRow = gridRow + 1
          const cornerCol = gridCol + 1
          // Idle diagonal marks are drawn as CSS lines (see
          // .connector-diagonal::before), not text glyphs -- a bare "\"
          // and "/" character overlaid at this tiny size don't reliably
          // read as an X across fonts, so idleGlyph is left empty here.
          cellsHtml += this.renderConnector(r, c, r + 1, c + 1, cornerRow, cornerCol, "connector-diagonal connector-diagonal-tlbr", connectorMap, "")
          cellsHtml += this.renderConnector(r, c + 1, r + 1, c, cornerRow, cornerCol, "connector-diagonal connector-diagonal-trbl", connectorMap, "")
        }
      })
    })

    this.gridTarget.innerHTML = `<div class="grid-rows" style="grid-template-columns:${gridTemplateTracks(size)};grid-template-rows:${gridTemplateTracks(size)};">${cellsHtml}</div>`
    this.justRefreshedCells = [] // one-shot: don't replay the flip on the next unrelated render
  }

  // A single connector glyph in the gutter (or, for a diagonal, the box
  // corner) between (r1,c1) and (r2,c2). idleGlyph by default; +/x
  // (with a little pop-in) when that exact pair is a consecutive link
  // in the current chain.
  renderConnector(r1, c1, r2, c2, gridRow, gridCol, orientation, connectorMap, idleGlyph = "\u2013") {
    const op = connectorMap.get(connectorKey({ row: r1, col: c1 }, { row: r2, col: c2 }))
    const classes = ["connector", ...orientation.split(" ")]
    let glyph = idleGlyph

    if (op === "+") {
      classes.push("connector-active", "connector-plus")
      glyph = "+"
    } else if (op === "*") {
      classes.push("connector-active", "connector-times")
      glyph = "\u00D7"
    }

    return `<span class="${classes.join(" ")}" style="grid-row:${gridRow};grid-column:${gridCol};">${glyph}</span>`
  }

  // Targets no longer sit around marked "claimed" -- the moment one is
  // claimed it's gone, replaced by a fresh one. A brand-new id (one we
  // haven't rendered before) gets a "pop in" animation so the rotation
  // reads as a continuous flow rather than a silent swap.
  //
  // Each chip's material (crystal/emerald/diamond) is derived purely
  // from its value -- bigger numbers look rarer, the same way a mining
  // game's loot table would read at a glance -- and shares its exact
  // breakpoints with ClaimService.points_for_value server-side, so a
  // prize's color and its "worth N pts" label always agree. The base
  // point value comes straight from the server (see
  // GameStatePresenter#targets_json) rather than being recomputed here,
  // since ClaimService is the one real source of truth for it.
  renderTargets() {
    const html = (this.stateValue.targets || []).map((t) => {
      const classes = ["target-chip", this.materialTierClass(t.value)]
      if (this.justArrivedIds.includes(t.id)) classes.push("just-arrived")
      return `<span class="${classes.join(" ")}"><span class="target-chip-value">${t.value}</span><span class="target-chip-points">${t.points} pts</span></span>`
    }).join("")

    this.targetsTarget.innerHTML = html
    this.justArrivedIds = [] // one-shot: don't replay the pop on the next unrelated render
  }

  materialTierClass(value) {
    if (value <= 20) return "tier-crystal"
    if (value <= 100) return "tier-emerald"
    return "tier-diamond"
  }

  renderScoreboard() {
    const players = this.stateValue.players || []
    if (players.length === 0) {
      this.scoreboardTarget.innerHTML = ""
      return
    }

    this.scoreboardTarget.innerHTML = players.map((p) => {
      const mine = p.user_id === this.currentUserIdValue ? " (you)" : ""
      return `<span class="score-chip">${p.name}${mine}: <strong>${p.points} pts</strong></span>`
    }).join("")
  }

  renderTimer() {
    if (!this.hasTimerTarget) return

    const remaining = Math.max(0, Math.round(this.remainingSeconds ?? 0))
    const mins = Math.floor(remaining / 60)
    const secs = remaining % 60
    const urgent = remaining <= 10 && this.stateValue.status === "active"
    const claims = this.stateValue.claims_count ?? 0

    this.timerTarget.innerHTML = `
      <div class="timer-clock${urgent ? " timer-urgent" : ""}">${mins}:${String(secs).padStart(2, "0")}</div>
      <div class="claims-count">${claims} claimed</div>
    `
  }

  renderExpression() {
    if (this.path.length === 0) {
      this.expressionTarget.textContent = "\u2014"
      return
    }

    let str = String(this.path[0].value)
    this.ops.forEach((op, i) => {
      str += ` ${op === "*" ? "\u00D7" : "+"} ${this.path[i + 1].value}`
    })

    // Show the running total live as the chain is built, not just in the
    // floating popup after a claim -- e.g. "6 x 7" becomes "6 x 7 = 42"
    // the moment there's at least one link to actually compute.
    if (this.ops.length > 0) {
      str += ` = ${this.currentChainValue()}`
    }

    this.expressionTarget.textContent = str
  }

  // Shown right next to the running expression: this player's current
  // point total for the round so far (not a preview of what the
  // in-progress chain would be worth -- that's what the expression
  // itself already shows via its running math).
  renderPointsTotal() {
    if (!this.hasPointsTotalTarget) return

    const players = this.stateValue.players || []
    const mine = players.find((p) => p.user_id === this.currentUserIdValue)
    const points = mine ? mine.points : 0
    this.pointsTotalTarget.textContent = `${points} pts`
  }

  // ----------------------------------------------------------- interaction

  cellClicked(event) {
    if (this.stateValue.status === "completed") return
    if (this.submitting) return // ignore clicks while an auto-submit is still resolving

    const row = parseInt(event.currentTarget.dataset.row, 10)
    const col = parseInt(event.currentTarget.dataset.col, 10)

    if (this.pendingCell && this.pendingCell.row === row && this.pendingCell.col === col) {
      clearTimeout(this.pendingTimer)
      this.pendingTimer = null
      this.pendingCell = null
      this.chooseCell(row, col, "*")
      return
    }

    if (this.pendingTimer) clearTimeout(this.pendingTimer)
    this.pendingCell = { row, col }
    this.pendingTimer = setTimeout(() => {
      this.chooseCell(row, col, "+")
      this.pendingTimer = null
      this.pendingCell = null
    }, DOUBLE_CLICK_MS)
  }

  chooseCell(row, col, op) {
    const lastIndex = this.path.length - 1

    if (lastIndex >= 0 && this.path[lastIndex].row === row && this.path[lastIndex].col === col) {
      this.path.pop()
      this.ops.pop()
      playRemove()
      this.render()
      return
    }

    if (this.path.some((p) => p.row === row && p.col === col)) return

    const value = this.stateValue.grid[row][col]

    if (this.path.length === 0) {
      this.path.push({ row, col, value })
      playAdd(0)
    } else {
      const prev = this.path[lastIndex]
      // Orthogonal neighbors link through the gutter dash; diagonal
      // neighbors link through the criss-cross mark at the shared
      // corner of their 2x2 box (see renderGrid) -- any diagonal pair
      // within the grid always has one, since all four cells of that
      // box necessarily exist too.
      const adjacent = Math.abs(prev.row - row) <= 1 && Math.abs(prev.col - col) <= 1
      if (!adjacent) {
        // Pivot to a fresh chain starting here, rather than rejecting
        // the click -- forcing the player to manually clear an old
        // chain just to start on a different number was never
        // actually useful friction, just an extra step.
        this.path = [{ row, col, value }]
        this.ops = []
        playAdd(0)
        this.render()
        this.maybeAutoSubmit()
        return
      }
      this.path.push({ row, col, value })
      this.ops.push(op)
      op === "*" ? playMultiply(this.path.length) : playAdd(this.path.length)
    }

    this.render()
    this.maybeAutoSubmit()
  }

  // The moment a link completes a chain that matches a currently open
  // target, submit it immediately -- no manual "Check" click needed.
  // This mirrors the server's own left-to-right evaluation so the
  // auto-fire moment matches what the server will actually accept; the
  // server still re-validates everything from scratch regardless.
  maybeAutoSubmit() {
    if (this.path.length < 2) return

    const value = this.currentChainValue()
    const matchesOpenTarget = (this.stateValue.targets || []).some((t) => t.value === value)

    if (matchesOpenTarget) this.submitPath()
  }

  currentChainValue() {
    let value = this.path[0].value
    this.ops.forEach((op, i) => {
      const next = this.path[i + 1].value
      value = op === "*" ? value * next : value + next
    })
    return value
  }

  clearPath() {
    this.path = []
    this.ops = []
    this.render()
  }

  async submitPath() {
    if (this.submitting) return

    if (this.path.length < 2) {
      this.flashMessage("Link at least two numbers first.", "warning")
      return
    }

    this.submitting = true
    const coords = this.path.map((p) => [p.row, p.col])
    // Captured before path/ops get cleared below, so the popup can show
    // exactly what was just solved and where it happened on the board.
    const expressionForPopup = this.expressionTarget.textContent
    const popupPosition = this.pathCentroidPercent()

    let data
    try {
      const response = await fetch(this.submitUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken(),
          Accept: "application/json"
        },
        body: JSON.stringify({ coords, ops: this.ops })
      })
      data = await response.json()
    } catch (e) {
      this.submitting = false
      this.flashMessage("Connection error, try again.", "warning")
      return
    }

    this.submitting = false
    this.path = []
    this.ops = []

    if (data.game) this.applyIncomingState(data.game)

    if (data.result && data.result.success) {
      playClaim()
      const { value, points, multiplier, chain_length: chainLength, chain_bonus: chainBonus, target_id: targetId } = data.result
      const chainNote = chainBonus > 1 ? ` \u00B7 ${chainLength}-chain!` : ""
      this.flashMessage(`Claimed ${value}! +${points} pts (${multiplier}x${chainNote})`, "success")
      this.showRewardSequence({ expressionForPopup, value, points, multiplier, chainLength, chainBonus, position: popupPosition })
      // Lets other controllers on this same element (see demo_controller.js)
      // react to a successful claim without grid_controller needing to know
      // anything about them -- e.g. the demo walkthrough waits for this to
      // know its guided chain actually went through server-side, rather
      // than just assuming its own client-side submission succeeded.
      this.element.dispatchEvent(new CustomEvent("grid:claimed", {
        bubbles: true, detail: { value, points, multiplier, targetId }
      }))
    } else if (data.result) {
      playFail()
      this.flashMessage(data.result.message || "No matching target.", "warning")
    } else {
      this.render()
    }
  }

  // Reward popups cascade one at a time -- equation, then points, then
  // (only for a 4+ cell chain) the chain-length bonus -- each one
  // popping in right as the previous one is nearly faded out, rather
  // than all launching together and piling up on the same spot.
  // REWARD_STEP_MS is tuned against each popup's own CSS animation
  // duration (see the *-popup-float keyframes in application.css) so
  // the handoff lands in that "almost faded" window. Each step also
  // gets its own chime, climbing one step higher than the last (see
  // sfx.js#playReward), so the cascade sounds like it's building same
  // as it looks.
  showRewardSequence({ expressionForPopup, value, points, multiplier, chainLength, chainBonus, position }) {
    const REWARD_STEP_MS = 650
    let step = 0

    playReward(step)
    this.showSolvePopup(`${expressionForPopup} = ${value}`, position)

    setTimeout(() => {
      step += 1
      playReward(step)
      this.showPointsPopup(points, multiplier, position)
    }, REWARD_STEP_MS)

    if (chainBonus > 1) {
      setTimeout(() => {
        step += 1
        playReward(step)
        this.showChainPopup(chainLength, position)
      }, REWARD_STEP_MS * 2)
    }
  }

  // Center point (as a percentage of the grid's width/height) of the
  // chain that was just submitted, so the popup appears right where the
  // solve actually happened rather than in some fixed generic spot.
  // Measured from actual DOM positions rather than assumed uniform
  // spacing -- the connector gutters between cells mean columns/rows
  // aren't all the same size, so a formula based on row/col index alone
  // would drift off target.
  pathCentroidPercent() {
    const gridRect = this.gridTarget.getBoundingClientRect()
    const centers = this.path.map((p) => {
      const cellEl = this.gridTarget.querySelector(`[data-row="${p.row}"][data-col="${p.col}"]`)
      if (!cellEl) return null
      const rect = cellEl.getBoundingClientRect()
      return {
        x: rect.left - gridRect.left + rect.width / 2,
        y: rect.top - gridRect.top + rect.height / 2
      }
    }).filter(Boolean)

    if (centers.length === 0) return { x: 50, y: 50 }

    const avgX = centers.reduce((sum, p) => sum + p.x, 0) / centers.length
    const avgY = centers.reduce((sum, p) => sum + p.y, 0) / centers.length
    return { x: (avgX / gridRect.width) * 100, y: (avgY / gridRect.height) * 100 }
  }

  // Floats a translucent "3 + 5 = 8" label up from the solved chain's
  // location and fades it out. Appended to popupLayerTarget, which sits
  // OUTSIDE gridTarget specifically so grid re-renders never wipe it out
  // mid-animation. First in the reward cascade -- see
  // showRewardSequence for how the other two are timed relative to it.
  showSolvePopup(text, position) {
    if (!this.hasPopupLayerTarget) return

    const el = document.createElement("div")
    el.className = "solve-popup"
    el.style.left = `${position.x}%`
    el.style.top = `${position.y}%`
    el.textContent = text

    this.popupLayerTarget.appendChild(el)
    el.addEventListener("animationend", () => el.remove())
    setTimeout(() => el.remove(), 1000) // safety net in case animationend never fires
  }

  // A second popup for the points a claim actually earned -- see
  // showRewardSequence, which schedules this to appear right as
  // showSolvePopup's own popup is nearly faded, rather than launching
  // together. Colored by the chain's multiplier tier using the SAME
  // sky/amber/fuchsia palette as cellValueColorClass, so "what color
  // just flashed" always tells you which digit band earned that
  // multiplier.
  showPointsPopup(points, multiplier, position) {
    if (!this.hasPopupLayerTarget || !points) return

    const el = document.createElement("div")
    el.className = `points-popup ${this.multiplierColorClass(multiplier)}`
    el.style.left = `${position.x}%`
    el.style.top = `${position.y}%`
    el.textContent = `+${points} pts \u00B7 ${multiplier}x`

    this.popupLayerTarget.appendChild(el)
    el.addEventListener("animationend", () => el.remove())
    setTimeout(() => el.remove(), 1000) // safety net in case animationend never fires
  }

  multiplierColorClass(multiplier) {
    if (multiplier <= 3) return "points-popup-low"
    if (multiplier <= 5) return "points-popup-mid"
    return "points-popup-high"
  }

  // A third popup, only for chains long enough to earn the length bonus
  // (4+ cells -- see ClaimService::MIN_CHAIN_LENGTH_FOR_BONUS). Last in
  // the reward cascade (see showRewardSequence), and reads as "NxN
  // CHAIN!!" (e.g. a 4-cell chain shows "4x 4CHAIN!!") since the bonus
  // always equals the chain's own length by design -- the bigger the
  // chain, the bigger both numbers get, together.
  showChainPopup(chainLength, position) {
    if (!this.hasPopupLayerTarget || !chainLength) return

    const el = document.createElement("div")
    el.className = "chain-popup"
    // Nudged sideways from the shared launch point -- even with the
    // cascade staggered in time, both popups float straight up from the
    // same spot, so this keeps them from sitting exactly on top of each
    // other during their brief handoff overlap.
    const offsetX = Math.min(92, Math.max(8, position.x + 10))
    el.style.left = `${offsetX}%`
    el.style.top = `${position.y}%`
    el.textContent = `${chainLength}x ${chainLength}CHAIN!!`

    this.popupLayerTarget.appendChild(el)
    el.addEventListener("animationend", () => el.remove())
    setTimeout(() => el.remove(), 1100) // safety net in case animationend never fires
  }

  // Captures each claimed cell's ACTUAL on-screen position and size
  // synchronously -- before the caller's upcoming render() rebuilds the
  // grid's HTML and destroys these exact DOM nodes -- so the spark burst
  // can be positioned and sized precisely, rather than guessing from a
  // generic small radius.
  spawnShatterForCells(cellKeys) {
    cellKeys.forEach((key) => {
      const [row, col] = key.split(",").map(Number)
      const cellEl = this.gridTarget.querySelector(`[data-row="${row}"][data-col="${col}"]`)
      const hostEl = this.popupLayerTarget
      if (!cellEl || !this.hasPopupLayerTarget) return

      const cellRect = cellEl.getBoundingClientRect()
      const hostRect = hostEl.getBoundingClientRect()
      const geometry = {
        xPx: cellRect.left - hostRect.left + cellRect.width / 2,
        yPx: cellRect.top - hostRect.top + cellRect.height / 2,
        sizePx: cellRect.width
      }

      this.spawnShatterEffect(row, col, geometry) // async internally; fire-and-forget is fine here
      this.scheduleExplosionReveal(row, col)
    })
  }

  // The claimed cell renders instantly hidden (see .cell.exploding) so
  // the new number doesn't appear underneath the still-flying debris.
  // After the explosion has mostly played out, fade it back in to
  // reveal the new number -- looked up fresh since render() has
  // replaced the DOM node by the time this timeout fires.
  scheduleExplosionReveal(row, col) {
    setTimeout(() => {
      const cellEl = this.gridTarget.querySelector(`[data-row="${row}"][data-col="${col}"]`)
      cellEl?.classList.remove("exploding")
    }, EXPLOSION_REVEAL_DELAY_MS)
  }

  // Tries the richer PixiJS particle burst first; if that's unavailable
  // for any reason (see pixi_shatter.js -- CDN issue, no WebGL, etc.),
  // falls back automatically to a CSS-based version. Either way the
  // player sees SOME shatter effect; only which one varies.
  async spawnShatterEffect(row, col, geometry) {
    if (!this.hasPopupLayerTarget) return

    const handledByPixi = await spawnPixiShatter(this.popupLayerTarget, geometry.xPx, geometry.yPx, geometry.sizePx)
    if (handledByPixi) return

    const size = this.stateValue.grid.length
    const cx = ((col + 0.5) / size) * 100
    const cy = ((row + 0.5) / size) * 100
    const pieceCount = 14

    for (let i = 0; i < pieceCount; i++) {
      const piece = document.createElement("div")
      piece.className = "shatter-piece"

      const angle = (Math.PI * 2 * i) / pieceCount + (Math.random() * 0.5 - 0.25)
      const distance = 36 + Math.random() * 26
      const dx = (Math.cos(angle) * distance).toFixed(1)
      const dy = (Math.sin(angle) * distance).toFixed(1)
      const rot = (Math.random() * 360 - 180).toFixed(0)
      const sparkColor = SPARK_COLORS[i % SPARK_COLORS.length]

      piece.style.left = `${cx}%`
      piece.style.top = `${cy}%`
      piece.style.setProperty("--dx", `${dx}px`)
      piece.style.setProperty("--dy", `${dy}px`)
      piece.style.setProperty("--rot", `${rot}deg`)
      piece.style.setProperty("--piece-color", sparkColor)

      this.popupLayerTarget.appendChild(piece)
      piece.addEventListener("animationend", () => piece.remove())
      setTimeout(() => piece.remove(), 900) // safety net in case animationend never fires
    }
  }

  flashMessage(text, kind = "info") {
    this.messageTarget.textContent = text
    this.messageTarget.className = `game-message game-message-${kind}`
    clearTimeout(this._flashTimer)
    this._flashTimer = setTimeout(() => {
      this.messageTarget.textContent = ""
    }, 3000)
  }

  csrfToken() {
    const el = document.querySelector('meta[name="csrf-token"]')
    return el ? el.content : ""
  }
}
