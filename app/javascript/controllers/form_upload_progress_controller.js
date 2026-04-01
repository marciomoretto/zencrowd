import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["progressWrapper", "progressBar", "status", "submit"]

  connect() {
    this.intervalId = null
    this.progressValue = 0
    this.defaultSubmitLabel = this.readSubmitLabel()
  }

  disconnect() {
    this.stopAnimation()
  }

  submit() {
    const files = this.selectedFiles()
    if (files.length === 0) return

    this.showProgress()
    this.disableSubmit()
    this.startAnimation()
  }

  selectedFiles() {
    const fileInputs = Array.from(this.element.querySelectorAll('input[type="file"][multiple]'))
    return fileInputs.flatMap((input) => Array.from(input.files || []))
  }

  showProgress() {
    if (this.hasProgressWrapperTarget) {
      this.progressWrapperTarget.classList.remove("d-none")
    }

    if (this.hasStatusTarget) {
      this.statusTarget.textContent = "Enviando imagens..."
    }
  }

  disableSubmit() {
    if (!this.hasSubmitTarget) return

    this.submitTarget.disabled = true
    this.writeSubmitLabel("Enviando...")
  }

  startAnimation() {
    this.stopAnimation()

    this.progressValue = 10
    this.renderProgress()

    this.intervalId = window.setInterval(() => {
      this.progressValue = Math.min(this.progressValue + 3, 90)
      this.renderProgress()
    }, 250)
  }

  stopAnimation() {
    if (this.intervalId) {
      window.clearInterval(this.intervalId)
      this.intervalId = null
    }
  }

  renderProgress() {
    if (!this.hasProgressBarTarget) return

    this.progressBarTarget.style.width = `${this.progressValue}%`
    this.progressBarTarget.textContent = `${this.progressValue}%`
  }

  readSubmitLabel() {
    if (!this.hasSubmitTarget) return ""

    if ("value" in this.submitTarget && this.submitTarget.value) {
      return this.submitTarget.value
    }

    return this.submitTarget.textContent || ""
  }

  writeSubmitLabel(text) {
    if (!this.hasSubmitTarget) return

    if ("value" in this.submitTarget && this.submitTarget.value !== undefined) {
      this.submitTarget.value = text
      return
    }

    this.submitTarget.textContent = text
  }
}