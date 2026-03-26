import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["progressWrapper", "progressBar", "status", "error", "previewWrapper", "previewImage"]
  static values = { statusUrl: String }

  connect() {
    this.pollTimer = null
    this.pollInFlight = false

    if (this.hasStatusUrlValue) {
      this.setStatus("Mosaico enfileirado para processamento...")
      this.setProgress(0)
      this.startPolling(this.statusUrlValue)
    }
  }

  disconnect() {
    this.stopPolling()
  }

  startPolling(statusUrl) {
    this.stopPolling()
    this.resetError()

    this.fetchProgress(statusUrl)
    this.pollTimer = window.setInterval(() => this.fetchProgress(statusUrl), 800)
  }

  stopPolling() {
    if (!this.pollTimer) {
      return
    }

    window.clearInterval(this.pollTimer)
    this.pollTimer = null
  }

  async fetchProgress(statusUrl) {
    if (this.pollInFlight) {
      return
    }

    this.pollInFlight = true

    try {
      const response = await fetch(statusUrl, {
        method: "GET",
        credentials: "same-origin",
        headers: { "Accept": "application/json" }
      })

      const payload = await response.json().catch(() => ({}))
      if (!response.ok) {
        throw new Error(payload.error || "Falha ao consultar progresso do mosaico.")
      }

      this.setProgress(this.integerOrDefault(payload.progress, this.currentProgress()))
      this.setStatus(payload.message || "Gerando mosaico...")

      if (payload.status === "completed") {
        this.stopPolling()
        this.setProgress(100)
        this.setStatus(payload.message || "Mosaico finalizado.")
        this.hideProgress()

        if (payload.preview_url) {
          this.showPreview(payload.preview_url)
        }

        return
      }

      if (payload.status === "failed") {
        throw new Error(payload.error || payload.message || "Falha ao gerar mosaico.")
      }
    } catch (error) {
      this.stopPolling()
      this.showError(error.message || "Erro ao acompanhar o mosaico.")
    } finally {
      this.pollInFlight = false
    }
  }

  resetError() {
    if (!this.hasErrorTarget) {
      return
    }

    this.errorTarget.textContent = ""
    this.errorTarget.classList.add("d-none")
  }

  showError(message) {
    if (!this.hasErrorTarget) {
      return
    }

    this.errorTarget.textContent = message
    this.errorTarget.classList.remove("d-none")
  }

  integerOrDefault(value, fallback) {
    const parsed = parseInt(value, 10)
    return Number.isNaN(parsed) ? fallback : parsed
  }

  currentProgress() {
    if (!this.hasProgressBarTarget) {
      return 0
    }

    const value = parseInt(this.progressBarTarget.dataset.progressValue || "0", 10)
    return Number.isNaN(value) ? 0 : value
  }

  setProgress(value) {
    if (!this.hasProgressBarTarget) {
      return
    }

    this.progressBarTarget.dataset.progressValue = String(value)
    this.progressBarTarget.style.width = `${value}%`
    this.progressBarTarget.textContent = `${value}%`
  }

  setStatus(message) {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = message
    }
  }

  hideProgress() {
    if (this.hasProgressWrapperTarget) {
      this.progressWrapperTarget.classList.add("d-none")
    }
  }

  showPreview(previewUrl) {
    if (!this.hasPreviewWrapperTarget || !this.hasPreviewImageTarget) {
      return
    }

    this.previewImageTarget.src = previewUrl
    this.previewWrapperTarget.classList.remove("d-none")
  }
}
