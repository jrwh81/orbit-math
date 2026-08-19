import { Controller } from "@hotwired/stimulus"

// Solo-only guided walkthrough: highlights a REAL, currently-solvable
// chain on the board (computed server-side, see SoloGamesController
// #demo_path_for) one step at a time -- "click here to start", "click
// here to add", "double-click here to multiply" -- then, once the
// player's own clicks actually land a claim, congratulates them and
// asks whether to see another one or turn the whole thing off.
//
// This controller NEVER submits a chain itself. It only watches the
// player's real clicks against the expected coordinates and reacts;
// grid_controller.js (also attached to this same element -- see
// games/_board.html.erb) does 100% of the actual gameplay, exactly as
// it would with no demo running at all.
export default class extends Controller {
  static targets = ["checkbox"]
  static values = {
    enabled: Boolean,
    pathUrl: String,
    modeUrl: String,
    initialPath: Object
  }

  connect() {
    this.stepIndex = 0
    this.awaitingSecondClick = false
    this.active = false
    this.highlightEl = null
    this.bubbleEl = null
    this.congratsEl = null

    // Capture phase, not bubble -- this needs to see the click and
    // record our own progress before grid_controller's own bubble-phase
    // handler (data-action="click->grid#cellClicked") runs its own
    // logic and, on a matching click, re-renders the grid's DOM.
    this.onGridClick = this.onGridClick.bind(this)
    this.onClaimed = this.onClaimed.bind(this)
    this.element.addEventListener("click", this.onGridClick, true)
    this.element.addEventListener("grid:claimed", this.onClaimed)

    if (this.enabledValue && this.initialPathValue && this.initialPathValue.available) {
      this.startDemo(this.initialPathValue)
    }
  }

  disconnect() {
    this.element.removeEventListener("click", this.onGridClick, true)
    this.element.removeEventListener("grid:claimed", this.onClaimed)
    this.clearBubble()
    this.clearHighlight()
    this.clearCongrats()
  }

  startDemo(pathData) {
    this.coords = pathData.coords
    this.ops = pathData.ops
    this.targetId = pathData.target_id
    this.stepIndex = 0
    this.awaitingSecondClick = false
    this.active = true
    this.showStep()
  }

  endDemo() {
    this.active = false
    this.clearBubble()
    this.clearHighlight()
  }

  // Tracks the player's real clicks against the expected chain. A
  // matching click on the LAST cell just advances state here and waits
  // for "grid:claimed" (see onClaimed) to actually confirm the win --
  // this controller never assumes success on its own. Any click that
  // doesn't match the expected next cell quietly ends the demo rather
  // than fighting the player's own game.
  //
  // A multiply step needs TWO real clicks on the same cell -- and since
  // grid_controller commits every click immediately now (no more
  // wait-and-see delay before deciding +/x), it re-renders the grid's
  // DOM on EACH of those two clicks, not just the second. So both
  // branches below defer past that render before touching anything:
  // the first click re-highlights the SAME cell (stepIndex hasn't
  // advanced yet) to keep the ring alive while awaiting the second
  // click; the second click moves on to whichever cell is next.
  onGridClick(event) {
    if (!this.active) return

    const cellEl = event.target.closest(".cell")
    if (!cellEl) return

    const row = parseInt(cellEl.dataset.row, 10)
    const col = parseInt(cellEl.dataset.col, 10)
    const expected = this.coords[this.stepIndex]

    if (!expected || expected[0] !== row || expected[1] !== col) {
      this.endDemo()
      return
    }

    const needsDouble = this.stepIndex > 0 && this.ops[this.stepIndex - 1] === "*"
    if (needsDouble && !this.awaitingSecondClick) {
      this.awaitingSecondClick = true
      setTimeout(() => this.showStep(), 0)
      return
    }
    this.awaitingSecondClick = false
    this.stepIndex += 1

    setTimeout(() => {
      if (this.stepIndex < this.coords.length) {
        this.showStep()
      } else {
        this.clearBubble()
        this.clearHighlight()
      }
    }, 0)
  }

  onClaimed(event) {
    if (!this.active) return
    if (this.stepIndex < this.coords.length) return // some other claim, not ours -- ignore

    this.active = false
    this.showCongrats(event.detail)
  }

  showStep() {
    this.clearBubble()
    this.clearHighlight()

    const [row, col] = this.coords[this.stepIndex]
    const cellEl = this.element.querySelector(`[data-row="${row}"][data-col="${col}"]`)
    if (!cellEl) {
      this.endDemo() // board changed out from under us -- bail rather than point at nothing
      return
    }

    cellEl.classList.add("demo-highlight")
    this.highlightEl = cellEl

    const bubble = document.createElement("div")
    bubble.className = "demo-bubble"
    bubble.textContent = this.stepMessage()
    this.element.appendChild(bubble)
    this.positionBubble(bubble, cellEl)
    this.bubbleEl = bubble
  }

  stepMessage() {
    if (this.stepIndex === 0) return "Click here to start a chain!"
    const op = this.ops[this.stepIndex - 1]
    return op === "*" ? "Double-click here to multiply!" : "Click here to add!"
  }

  positionBubble(bubble, cellEl) {
    const rect = cellEl.getBoundingClientRect()
    bubble.style.left = `${rect.left + rect.width / 2}px`
    bubble.style.top = `${rect.top}px`
  }

  clearBubble() {
    if (this.bubbleEl) {
      this.bubbleEl.remove()
      this.bubbleEl = null
    }
  }

  clearHighlight() {
    if (this.highlightEl) {
      this.highlightEl.classList.remove("demo-highlight")
      this.highlightEl = null
    }
  }

  showCongrats(detail) {
    const el = document.createElement("div")
    el.className = "stats-overlay demo-overlay"
    el.innerHTML = `
      <div class="stats-modal">
        <h2>Nice work! \u{1F389}</h2>
        <p class="demo-congrats-copy">
          That chain was worth <strong>${detail.points} pts</strong>
          (${detail.multiplier}&times; multiplier).
        </p>
        <div class="stats-actions">
          <button type="button" class="btn btn-secondary" data-action="demo#again">Show me again</button>
          <button type="button" class="btn btn-primary" data-action="demo#turnOff">Turn off demo mode</button>
        </div>
      </div>
    `
    this.element.appendChild(el)
    this.congratsEl = el
  }

  clearCongrats() {
    if (this.congratsEl) {
      this.congratsEl.remove()
      this.congratsEl = null
    }
  }

  // "Show me again" on the congrats screen -- fetches a FRESH chain
  // (the one just solved is gone, its cells already regenerated) and
  // starts over.
  async again() {
    this.clearCongrats()
    const data = await this.fetchDemoPath()
    if (data && data.available) this.startDemo(data)
  }

  turnOff() {
    this.clearCongrats()
    this.setEnabled(false)
  }

  // The checkbox itself -- can flip the preference either direction,
  // not just off, so turning it back on mid-session works too.
  async toggle(event) {
    const enabled = event.target.checked
    this.setEnabled(enabled)

    if (enabled) {
      const data = await this.fetchDemoPath()
      if (data && data.available) this.startDemo(data)
    } else {
      this.endDemo()
    }
  }

  async fetchDemoPath() {
    try {
      const response = await fetch(this.pathUrlValue, { headers: { Accept: "application/json" } })
      return await response.json()
    } catch (e) {
      return null
    }
  }

  // Fire-and-forget on purpose -- the checkbox/button already reflects
  // the new state optimistically, and this is a low-stakes preference,
  // not something worth blocking the UI over if the network hiccups.
  setEnabled(enabled) {
    if (this.hasCheckboxTarget) this.checkboxTarget.checked = enabled

    fetch(this.modeUrlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "X-CSRF-Token": this.csrfToken(),
        Accept: "application/json"
      },
      body: `enabled=${enabled}`
    }).catch(() => {}) // best effort -- worst case the preference doesn't stick this one time
  }

  csrfToken() {
    const el = document.querySelector('meta[name="csrf-token"]')
    return el ? el.content : ""
  }
}
