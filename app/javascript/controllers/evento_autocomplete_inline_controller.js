import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["nomeInput", "eventoIdInput", "option", "display", "editor"]

  connect() {
    this.originalValue = this.hasNomeInputTarget ? this.nomeInputTarget.value : ""
    this.sync()
  }

  open(event) {
    event.preventDefault()
    this.toggleEditor(true)

    if (this.hasNomeInputTarget) {
      this.nomeInputTarget.focus()
      this.nomeInputTarget.select()
    }
  }

  close(event) {
    event.preventDefault()

    if (this.hasNomeInputTarget) {
      this.nomeInputTarget.value = this.originalValue
    }

    this.sync()
    this.toggleEditor(false)
  }

  sync() {
    if (!this.hasNomeInputTarget || !this.hasEventoIdInputTarget) return

    const typedValue = this.nomeInputTarget.value.trim()
    const matchingOption = this.optionTargets.find((option) => option.value === typedValue)

    this.eventoIdInputTarget.value = matchingOption ? matchingOption.dataset.eventoId : ""
  }

  clear(event) {
    event.preventDefault()

    if (this.hasNomeInputTarget) this.nomeInputTarget.value = ""
    if (this.hasEventoIdInputTarget) this.eventoIdInputTarget.value = ""

    if (this.hasNomeInputTarget) {
      this.nomeInputTarget.focus()
    }
  }

  toggleEditor(open) {
    if (this.hasDisplayTarget) {
      this.displayTarget.classList.toggle("d-none", open)
    }

    if (this.hasEditorTarget) {
      this.editorTarget.classList.toggle("d-none", !open)
    }
  }
}
