import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["rowsInput", "colsInput", "submit", "progressWrapper", "progressBar", "status", "counts", "error"]
  static values = { statusUrl: String, totalCount: Number, finalizeUrl: String }

  connect() {
    this.pollTimer = null
    this.pollInFlight = false
    this.completionUrl = null
    this.defaultSubmitLabel = this.hasSubmitTarget ? this.submitTarget.textContent.trim() : "Cortar"

    if (this.hasStatusUrlValue && this.statusUrlValue.length > 0) {
      const totalCount = this.hasTotalCountValue ? this.totalCountValue : 1
      this.completionUrl = this.hasFinalizeUrlValue ? this.finalizeUrlValue : null
      this.prepareProgress(totalCount)
      this.disableInputs()
      this.setStatus("Retomando contagem em andamento...")
      this.startPolling(this.statusUrlValue, totalCount)
    }
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

    const rows = this.integerOrDefault(this.hasRowsInputTarget ? this.rowsInputTarget.value : 1, 1)
    const cols = this.integerOrDefault(this.hasColsInputTarget ? this.colsInputTarget.value : 1, 1)
    const totalCount = rows * cols
    const formData = new FormData(this.element)

    this.prepareProgress(totalCount)
    this.disableInputs()

    const headers = { "Accept": "application/json" }
    const csrfToken = this.csrfToken()
    if (csrfToken) {
      headers["X-CSRF-Token"] = csrfToken
    }

    try {
      const response = await fetch(this.element.action, {
        method: "POST",
        credentials: "same-origin",
        headers,
        body: formData
      })

      const payload = await response.json().catch(() => ({}))
      if (!response.ok) {
        throw new Error(payload.error || "Nao foi possivel iniciar o corte do mosaico.")
      }

      const statusUrl = payload.status_url
      if (!statusUrl) {
        throw new Error("Nao foi possivel acompanhar o progresso do corte do mosaico.")
      }

      this.completionUrl = payload.finalize_url || null

      this.startPolling(statusUrl, totalCount)
    } catch (error) {
      this.showError(error.message || "Erro ao iniciar o corte do mosaico.")
      this.enableInputs()
    }
  }

  confirmSubmission(submitter) {
    const message = submitter?.dataset?.turboConfirm
    return !message || window.confirm(message)
  }

  prepareProgress(totalCount) {
    if (this.hasProgressWrapperTarget) {
      this.progressWrapperTarget.classList.remove("d-none")
    }

    this.updateProgress(0, totalCount)
    this.updateCounts(0, totalCount)
    this.setStatus("Corte iniciado. Preparando contagem...")
  }

  startPolling(statusUrl, fallbackTotal) {
    this.stopPolling()
    this.fetchProgress(statusUrl, fallbackTotal)
    this.pollTimer = window.setInterval(() => this.fetchProgress(statusUrl, fallbackTotal), 800)
  }

  stopPolling() {
    if (!this.pollTimer) {
      return
    }

    window.clearInterval(this.pollTimer)
    this.pollTimer = null
  }

  async fetchProgress(statusUrl, fallbackTotal) {
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
        throw new Error(payload.error || "Falha ao consultar progresso do corte do mosaico.")
      }

      const totalCount = this.integerOrDefault(payload.total_count, fallbackTotal)
      const processedCount = this.integerOrDefault(payload.processed_count, 0)

      this.updateProgress(processedCount, totalCount)
      this.updateCounts(processedCount, totalCount)
      this.setStatus(payload.message || "Contando recortes do mosaico...")

      if (payload.status === "completed") {
        this.stopPolling()
        this.enableInputs()
        this.setStatus(payload.message || "Contagem concluida.")
        this.hideProgress()

        const destinationUrl = this.completionUrl
        if (destinationUrl) {
          window.setTimeout(() => window.location.assign(destinationUrl), 300)
        }
        return
      }

      if (payload.status === "failed") {
        throw new Error(payload.error || payload.message || "Falha ao cortar e contar o mosaico.")
      }
    } catch (error) {
      this.stopPolling()
      this.enableInputs()
      this.showError(error.message || "Erro ao acompanhar o corte do mosaico.")
    } finally {
      this.pollInFlight = false
    }
  }

  updateProgress(processedCount, totalCount) {
    const safeTotal = totalCount > 0 ? totalCount : 1
    const percentage = Math.round((processedCount / safeTotal) * 100)

    if (this.hasProgressBarTarget) {
      this.progressBarTarget.style.width = `${percentage}%`
      this.progressBarTarget.textContent = `${percentage}%`
    }
  }

  updateCounts(processedCount, totalCount) {
    if (this.hasCountsTarget) {
      this.countsTarget.textContent = `Contados: ${processedCount} de ${totalCount}.`
    }
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

  disableInputs() {
    if (this.hasRowsInputTarget) {
      this.rowsInputTarget.disabled = true
    }

    if (this.hasColsInputTarget) {
      this.colsInputTarget.disabled = true
    }

    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = true
      this.submitTarget.textContent = "Processando..."
    }
  }

  enableInputs() {
    if (this.hasRowsInputTarget) {
      this.rowsInputTarget.disabled = false
    }

    if (this.hasColsInputTarget) {
      this.colsInputTarget.disabled = false
    }

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
}
