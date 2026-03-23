import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["submit", "progressWrapper", "progressBar", "status", "error"]

  connect() {
    this.pollTimer = null
    this.pollInFlight = false
    this.defaultSubmitLabel = this.hasSubmitTarget ? this.submitTarget.textContent.trim() : "Gerar mosaico"
  }

  disconnect() {
    this.stopPolling()
  }

  async submit(event) {
    event.preventDefault()

    if (!this.confirmSubmission(event.submitter)) {
      return
    }

    this.resetError()
    this.prepareProgress()

    const formData = new FormData(event.target)
    const headers = { "Accept": "application/json" }
    const csrfToken = this.csrfToken()
    if (csrfToken) {
      headers["X-CSRF-Token"] = csrfToken
    }

    try {
      const response = await fetch(event.target.action, {
        method: "POST",
        credentials: "same-origin",
        headers,
        body: formData
      })

      const payload = await response.json().catch(() => ({}))

      if (!response.ok) {
        throw new Error(payload.error || "Falha ao iniciar a geração do mosaico.")
      }

      const statusUrl = payload.status_url
      if (!statusUrl) {
        throw new Error("Nao foi possivel acompanhar o progresso do mosaico.")
      }

      this.startPolling(statusUrl)
    } catch (error) {
      this.showError(error.message || "Erro ao iniciar o mosaico.")
      this.enableSubmit()
    }
  }

  confirmSubmission(submitter) {
    const message = submitter?.form?.dataset?.turboConfirm
    return !message || window.confirm(message)
  }

  prepareProgress() {
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = true
      this.submitTarget.textContent = "Gerando..."
    }

    if (this.hasProgressWrapperTarget) {
      this.progressWrapperTarget.classList.remove("d-none")
    }

    this.setStatus("Mosaico enfileirado para processamento...")
    this.setProgress(0)
  }

  startPolling(statusUrl) {
    this.stopPolling()

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
        this.setStatus(payload.message || "Mosaico finalizado. Redirecionando...")

        const redirectUrl = payload.redirect_url || window.location.href
        window.setTimeout(() => window.location.assign(redirectUrl), 300)
        return
      }

      if (payload.status === "failed") {
        throw new Error(payload.error || payload.message || "Falha ao gerar mosaico.")
      }
    } catch (error) {
      this.stopPolling()
      this.showError(error.message || "Erro ao acompanhar o mosaico.")
      this.enableSubmit()
    } finally {
      this.pollInFlight = false
    }
  }

  enableSubmit() {
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = false
      this.submitTarget.textContent = this.defaultSubmitLabel
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

  csrfToken() {
    const tokenElement = document.querySelector("meta[name='csrf-token']")
    return tokenElement ? tokenElement.content : ""
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
}
