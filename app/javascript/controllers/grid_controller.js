import { Controller } from "@hotwired/stimulus"
import { playAdd, playMultiply, playRemove, playClaim, playFail, playVictory } from "sfx"

// Click a neighboring cell to link it with "+". Double-click a neighboring
// cell (second click within DOUBLE_CLICK_MS) to link it with "*" instead.
// Clicking the last cell in the chain again removes it. All evaluation
// shown here is a preview only -- the server re-validates and re-evaluates
// every submission from scratch.
const DOUBLE_CLICK_MS = 320

// How long the end-of-round stats screen stays up before automatically
// sending the player home. "Play again" / "Continue" both skip the wait.
const AUTO_HOME_DELAY_MS = 6000

export default class extends Controller {
  static targets = ["grid", "targets", "scoreboard", "timer", "expression", "pointsTotal", "message", "completion", "popupLayer"]
  static values = {
    submitUrl: String,
    finishUrl: String,
    newGameUrl: String,
    homeUrl: String,
    currentUserId: Number,
    state: Object
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

    this.completionTarget.innerHTML = `
      <div class="stats-overlay">
        <div class="stats-modal">
          <h2>${headline}</h2>
          <ul class="stats-list">
            <li><span class="stats-value">${mine.points}</span><span class="stats-label">points earned</span></li>
            <li><span class="stats-value">${mine.claims}</span><span class="stats-label">targets claimed</span></li>
            <li><span class="stats-value">${mine.longest_chain}</span><span class="stats-label">longest chain</span></li>
            <li><span class="stats-value">${mine.highest_value}</span><span class="stats-label">highest value claimed</span></li>
          </ul>
          <div class="stats-actions">
            <a href="${this.newGameUrlValue}" class="btn btn-secondary">Play again</a>
            <a href="${this.homeUrlValue}" class="btn btn-primary">Continue</a>
          </div>
          <p class="stats-auto-note">Heading back to home&hellip;</p>
        </div>
      </div>
    `

    setTimeout(() => {
      window.location.href = this.homeUrlValue
    }, AUTO_HOME_DELAY_MS)
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

  renderGrid() {
    const grid = this.stateValue.grid
    const size = grid.length
    const gameOver = this.stateValue.status === "completed"

    let cellsHtml = ""
    grid.forEach((row, r) => {
      cellsHtml += `<div class="grid-row">`
      row.forEach((value, c) => {
        const stepIndex = this.path.findIndex((p) => p.row === r && p.col === c)
        const isNewest = stepIndex !== -1 && stepIndex === this.path.length - 1
        const classes = ["cell"]
        if (stepIndex !== -1) classes.push("selected")
        if (isNewest) classes.push("just-grabbed")
        if (gameOver) classes.push("disabled")
        if (this.justRefreshedCells.includes(`${r},${c}`)) classes.push("just-refreshed")
        // Deterministic per-position variety (not random per render) so each
        // asteroid keeps the same irregular silhouette across re-renders,
        // instead of visibly reshaping itself on every click.
        const shape = (r * 3 + c * 5) % 5

        cellsHtml += `<button type="button" class="${classes.join(" ")}" data-row="${r}" data-col="${c}" data-shape="${shape}" data-action="click->grid#cellClicked">
          <span class="cell-value">${value}</span>
          ${stepIndex !== -1 ? `<span class="cell-order">${stepIndex + 1}</span>` : ""}
        </button>`
      })
      cellsHtml += `</div>`
    })

    this.gridTarget.innerHTML = `${this.renderChainSvg(size)}<div class="grid-rows">${cellsHtml}</div>`
    this.justRefreshedCells = [] // one-shot: don't replay the flip on the next unrelated render
  }

  // Draws a glowing line between each consecutive pair of cells in the
  // current chain, positioned with percentage coordinates so it scales
  // with the grid regardless of screen size. Because this whole block of
  // HTML is replaced on every render, each <line> is a brand-new DOM
  // node every time a link is added -- which means its CSS "draw in"
  // animation plays fresh every time, for free.
  renderChainSvg(size) {
    if (this.path.length < 2) {
      return `<svg class="chain-svg" viewBox="0 0 100 100" preserveAspectRatio="none"></svg>`
    }

    const centerFor = (r, c) => [((c + 0.5) / size) * 100, ((r + 0.5) / size) * 100]
    let lines = ""

    for (let i = 0; i < this.path.length - 1; i++) {
      const [x1, y1] = centerFor(this.path[i].row, this.path[i].col)
      const [x2, y2] = centerFor(this.path[i + 1].row, this.path[i + 1].col)
      const isMultiply = this.ops[i] === "*"
      const kind = isMultiply ? "chain-line-multiply" : "chain-line-add"
      lines += `<line class="chain-line ${kind}" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}"></line>`
    }

    return `<svg class="chain-svg" viewBox="0 0 100 100" preserveAspectRatio="none">${lines}</svg>`
  }

  // Targets no longer sit around marked "claimed" -- the moment one is
  // claimed it's gone, replaced by a fresh one. A brand-new id (one we
  // haven't rendered before) gets a "pop in" animation so the rotation
  // reads as a continuous flow rather than a silent swap.
  //
  // Each chip's material (crystal/gold/emerald/platinum/diamond) is
  // derived purely from its value -- bigger numbers look rarer, the
  // same way a mining game's loot table would read at a glance.
  renderTargets() {
    const html = (this.stateValue.targets || []).map((t) => {
      const classes = ["target-chip", this.materialTierClass(t.value)]
      if (this.justArrivedIds.includes(t.id)) classes.push("just-arrived")
      return `<span class="${classes.join(" ")}">${t.value}</span>`
    }).join("")

    this.targetsTarget.innerHTML = html
    this.justArrivedIds = [] // one-shot: don't replay the pop on the next unrelated render
  }

  materialTierClass(value) {
    if (value <= 10) return "tier-crystal"
    if (value <= 20) return "tier-gold"
    if (value <= 50) return "tier-emerald"
    if (value <= 150) return "tier-platinum"
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
      const adjacent = Math.abs(prev.row - row) <= 1 && Math.abs(prev.col - col) <= 1
      if (!adjacent) {
        this.flashMessage("That asteroid isn't adjacent to your last link.", "warning")
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
      this.flashMessage("Link at least two asteroids first.", "warning")
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
      this.flashMessage(`Claimed ${data.result.value}!`, "success")
      this.showSolvePopup(`${expressionForPopup} = ${data.result.value}`, popupPosition)
    } else if (data.result) {
      playFail()
      this.flashMessage(data.result.message || "No matching target.", "warning")
    } else {
      this.render()
    }
  }

  // Center point (as a percentage of the grid's width/height) of the
  // chain that was just submitted, so the popup appears right where the
  // solve actually happened rather than in some fixed generic spot.
  pathCentroidPercent() {
    const size = this.stateValue.grid.length
    const avgRow = this.path.reduce((sum, p) => sum + p.row, 0) / this.path.length
    const avgCol = this.path.reduce((sum, p) => sum + p.col, 0) / this.path.length
    return { x: ((avgCol + 0.5) / size) * 100, y: ((avgRow + 0.5) / size) * 100 }
  }

  // Floats a translucent "3 + 5 = 8" label up from the solved chain's
  // location and fades it out. Appended to popupLayerTarget, which sits
  // OUTSIDE gridTarget specifically so grid re-renders never wipe it out
  // mid-animation.
  showSolvePopup(text, position) {
    if (!this.hasPopupLayerTarget) return

    const el = document.createElement("div")
    el.className = "solve-popup"
    el.style.left = `${position.x}%`
    el.style.top = `${position.y}%`
    el.textContent = text

    this.popupLayerTarget.appendChild(el)
    el.addEventListener("animationend", () => el.remove())
    setTimeout(() => el.remove(), 1800) // safety net in case animationend never fires
  }

  // Spawns a burst of small rock fragments flying outward from each cell
  // that just got a new value -- the "asteroid breaking apart" moment.
  // Also appended to popupLayerTarget for the same reason as the solve
  // popup: it needs to survive the grid re-render that's about to happen.
  spawnShatterForCells(cellKeys) {
    cellKeys.forEach((key) => {
      const [row, col] = key.split(",").map(Number)
      this.spawnShatterEffect(row, col)
    })
  }

  spawnShatterEffect(row, col) {
    if (!this.hasPopupLayerTarget || !this.stateValue.grid) return

    const size = this.stateValue.grid.length
    const cx = ((col + 0.5) / size) * 100
    const cy = ((row + 0.5) / size) * 100
    const pieceCount = 6

    for (let i = 0; i < pieceCount; i++) {
      const piece = document.createElement("div")
      piece.className = "shatter-piece"

      const angle = (Math.PI * 2 * i) / pieceCount + (Math.random() * 0.6 - 0.3)
      const distance = 24 + Math.random() * 18
      const dx = (Math.cos(angle) * distance).toFixed(1)
      const dy = (Math.sin(angle) * distance).toFixed(1)
      const rot = (Math.random() * 360 - 180).toFixed(0)

      piece.style.left = `${cx}%`
      piece.style.top = `${cy}%`
      piece.style.setProperty("--dx", `${dx}px`)
      piece.style.setProperty("--dy", `${dy}px`)
      piece.style.setProperty("--rot", `${rot}deg`)

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
