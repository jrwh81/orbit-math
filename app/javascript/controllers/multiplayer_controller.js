import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

// Subscribes to GameChannel for one multiplayer GameSession. Waiting-room
// events (opponent joined, host started the game) just reload the page --
// the simplest reliable way to move from lobby to live board. Once the
// game is active, move_result events are handed off to the grid
// controller sitting on the same element via a DOM CustomEvent so both
// players' boards, scores, and target chips stay in sync in real time.
export default class extends Controller {
  static values = {
    gameSessionId: Number,
    currentUserId: Number,
    waiting: Boolean
  }

  connect() {
    this.subscription = consumer.subscriptions.create(
      { channel: "GameChannel", game_session_id: this.gameSessionIdValue },
      { received: (data) => this.handleReceived(data) }
    )
  }

  disconnect() {
    if (this.subscription) this.subscription.unsubscribe()
  }

  handleReceived(data) {
    switch (data.event) {
      case "opponent_joined":
      case "game_started":
        window.location.reload()
        break
      case "move_result":
        // The player who made this move already got instant feedback
        // from their own fetch response (grid_controller#submitPath) --
        // skip re-applying it here so their sound/animation doesn't
        // double-fire when the broadcast echoes back to them too.
        if (data.result && data.result.user_id === this.currentUserIdValue) break

        this.element.dispatchEvent(
          new CustomEvent("grid:remote-update", { detail: data.game, bubbles: true })
        )
        break
      default:
        break
    }
  }
}
