import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  handle(event) {
    const app = this.element.__wpdMinimalApp
    if (event.button !== 2 || !app || event.target !== app.elements.canvas) return

    event.preventDefault()
    const before = new CustomEvent("wpd:before-alternate-point", { bubbles: true, cancelable: true })
    if (!this.element.dispatchEvent(before)) return

    const previousMode = app.mode
    const previousCount = app.points.length
    try {
      app.mode = previousMode === "add" ? "delete" : "add"
      app.handleCanvasClick(event)
    } finally {
      app.mode = previousMode
    }

    if (app.points.length !== previousCount) {
      this.element.dispatchEvent(new CustomEvent("wpd:alternate-point-changed", { bubbles: true }))
    }
  }
}
