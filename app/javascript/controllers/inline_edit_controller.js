import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["display", "editor", "focus"]

  connect() {
    this.initialValue = this.hasFocusTarget ? this.focusTarget.value : null
    this.toggle(false)
  }

  open(event) {
    event.preventDefault()
    this.toggle(true)

    if (this.hasFocusTarget) {
      this.focusTarget.focus()
      if (typeof this.focusTarget.select === "function") {
        this.focusTarget.select()
      }
    }
  }

  close(event) {
    event.preventDefault()

    if (this.hasFocusTarget && this.initialValue !== null) {
      this.focusTarget.value = this.initialValue
    }

    this.toggle(false)
  }

  toggle(open) {
    if (this.hasDisplayTarget) {
      this.displayTarget.classList.toggle("d-none", open)
    }

    if (this.hasEditorTarget) {
      this.editorTarget.classList.toggle("d-none", !open)
    }
  }
}