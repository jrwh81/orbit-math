import { Controller } from "@hotwired/stimulus"

// Simple show/hide toggle for the mobile nav menu. Deliberately doesn't
// try to auto-close on outside-click or on navigation -- clicking any
// link inside the open menu already navigates away, which naturally
// tears down and recreates this controller (a full page load, or a
// Turbo Drive body swap either way), resetting the menu closed for free.
export default class extends Controller {
  static targets = ["menu"]

  toggle() {
    const isOpen = this.menuTarget.classList.toggle("is-open")
    this.element.querySelector(".nav-toggle")?.setAttribute("aria-expanded", isOpen ? "true" : "false")
  }
}
