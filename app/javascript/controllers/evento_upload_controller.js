import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "progressWrapper", "progressBar", "status", "submit", "error"]

  connect() {
    this.defaultSubmitLabel = this.hasSubmitTarget ? this.submitTarget.value : ""
  }

  async submit(event) {
    const files = this.selectedFiles()
    if (files.length === 0) {
      return
    }

    event.preventDefault()
    this.resetError()
    this.prepareUploadState()

    let uploadedCount = 0
    let processedCount = 0
    let failedCount = 0

    for (const file of files) {
      const success = await this.uploadSingleFile(file)
      processedCount += 1

      if (success) {
        uploadedCount += 1
      } else {
        failedCount += 1
      }

      this.updateProgress(uploadedCount, processedCount, files.length, failedCount)
    }

    if (failedCount === 0) {
      this.statusTarget.textContent = `Envio concluido. Subidas: ${uploadedCount}. Faltam: 0.`
      window.location.reload()
      return
    }

    const missingCount = files.length - uploadedCount
    this.showError(`Falha no envio de ${failedCount} arquivo(s). Subidas: ${uploadedCount}. Faltam: ${missingCount}.`)
    this.enableInputs()
  }

  selectedFiles() {
    return this.hasInputTarget ? Array.from(this.inputTarget.files || []) : []
  }

  prepareUploadState() {
    if (this.hasProgressWrapperTarget) {
      this.progressWrapperTarget.classList.remove("d-none")
    }

    this.disableInputs()
    this.updateProgress(0, 0, this.selectedFiles().length, 0)
  }

  disableInputs() {
    if (this.hasInputTarget) {
      this.inputTarget.disabled = true
    }

    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = true
      this.submitTarget.value = "Enviando..."
    }
  }

  enableInputs() {
    if (this.hasInputTarget) {
      this.inputTarget.disabled = false
    }

    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = false
      this.submitTarget.value = this.defaultSubmitLabel || "Enviar imagem"
    }
  }

  updateProgress(uploadedCount, processedCount, totalCount, failedCount) {
    const safeTotal = totalCount > 0 ? totalCount : 1
    const percentage = Math.round((processedCount / safeTotal) * 100)

    if (this.hasProgressBarTarget) {
      this.progressBarTarget.style.width = `${percentage}%`
      this.progressBarTarget.textContent = `${percentage}%`
    }

    if (this.hasStatusTarget) {
      const missingCount = totalCount - uploadedCount
      const failuresText = failedCount > 0 ? ` Falhas: ${failedCount}.` : ""
      this.statusTarget.textContent = `Subidas: ${uploadedCount} de ${totalCount}. Faltam: ${missingCount}.${failuresText}`
    }
  }

  async uploadSingleFile(file) {
    const formData = new FormData()
    formData.append("evento[arquivo]", file)
    this.appendTextField(formData, "evento[pasta_existente]")
    this.appendTextField(formData, "evento[nova_pasta]")

    const headers = { "Accept": "application/json" }
    const csrfToken = this.csrfToken()
    if (csrfToken) {
      headers["X-CSRF-Token"] = csrfToken
    }

    try {
      const response = await fetch(this.element.action, {
        method: "PATCH",
        credentials: "same-origin",
        headers,
        body: formData
      })

      if (response.ok) {
        return true
      }

      const payload = await response.json().catch(() => ({}))
      const errors = Array.isArray(payload.errors) ? payload.errors : []
      if (errors.length > 0) {
        this.showError(errors.join(", "))
      }

      return false
    } catch (_error) {
      this.showError("Erro de rede durante o upload.")
      return false
    }
  }

  appendTextField(formData, fieldName) {
    const field = this.element.querySelector(`[name='${fieldName}']`)
    if (!field) {
      return
    }

    formData.append(fieldName, field.value || "")
  }

  csrfToken() {
    const tokenElement = document.querySelector("meta[name='csrf-token']")
    return tokenElement ? tokenElement.content : ""
  }

  resetError() {
    if (!this.hasErrorTarget) {
      return
    }

    this.errorTarget.textContent = ""
    this.errorTarget.classList.add("d-none")
  }

  showError(message) {
    if (!this.hasErrorTarget || !message) {
      return
    }

    this.errorTarget.textContent = message
    this.errorTarget.classList.remove("d-none")
  }
}
