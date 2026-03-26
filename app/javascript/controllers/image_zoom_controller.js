import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["canvas", "frame", "level", "zoomInButton", "zoomOutButton"]

  connect() {
    this.zoom = 1
    this.minZoom = 0.5
    this.maxZoom = 9
    this.step = 0.1
    this.isPanning = false
    this.panStartX = 0
    this.panStartY = 0
    this.scrollStartLeft = 0
    this.scrollStartTop = 0
    this.wheelHandler = this.zoomWithWheel.bind(this)

    if (this.hasFrameTarget) {
      this.frameTarget.addEventListener("wheel", this.wheelHandler, { passive: false })
    }

    this.applyZoom(this.zoom)
  }

  disconnect() {
    if (this.hasFrameTarget && this.wheelHandler) {
      this.frameTarget.removeEventListener("wheel", this.wheelHandler)
    }
  }

  zoomIn() {
    this.applyZoom(this.zoom + this.step)
  }

  zoomOut() {
    this.applyZoom(this.zoom - this.step)
  }

  startPan(event) {
    if (!this.hasFrameTarget || event.button !== 0) {
      return
    }

    this.isPanning = true
    this.panStartX = event.clientX
    this.panStartY = event.clientY
    this.scrollStartLeft = this.frameTarget.scrollLeft
    this.scrollStartTop = this.frameTarget.scrollTop

    this.frameTarget.classList.add("is-panning")
  }

  pan(event) {
    if (!this.hasFrameTarget || !this.isPanning) {
      return
    }

    event.preventDefault()

    const deltaX = event.clientX - this.panStartX
    const deltaY = event.clientY - this.panStartY

    this.frameTarget.scrollLeft = this.scrollStartLeft - deltaX
    this.frameTarget.scrollTop = this.scrollStartTop - deltaY
  }

  endPan() {
    if (!this.hasFrameTarget || !this.isPanning) {
      return
    }

    this.isPanning = false
    this.frameTarget.classList.remove("is-panning")
  }

  zoomWithWheel(event) {
    if (!this.hasFrameTarget) {
      return
    }

    if (document.activeElement !== this.frameTarget) {
      return
    }

    const previousScrollLeft = this.frameTarget.scrollLeft
    const previousScrollTop = this.frameTarget.scrollTop

    if (event.cancelable) {
      event.preventDefault()
    }
    event.stopPropagation()

    const direction = event.deltaY < 0 ? 1 : -1
    this.applyZoom(this.zoom + (direction * this.step))

    this.frameTarget.scrollLeft = previousScrollLeft
    this.frameTarget.scrollTop = previousScrollTop
  }

  resetView() {
    this.endPan()
    this.applyZoom(1)

    if (this.hasFrameTarget) {
      this.frameTarget.scrollLeft = 0
      this.frameTarget.scrollTop = 0
    }
  }

  applyZoom(value) {
    if (!this.hasCanvasTarget) {
      return
    }

    const clamped = Math.min(this.maxZoom, Math.max(this.minZoom, value))
    this.zoom = Number(clamped.toFixed(2))

    this.canvasTarget.style.width = `${(this.zoom * 100).toFixed(0)}%`

    if (this.hasLevelTarget) {
      this.levelTarget.textContent = `${Math.round(this.zoom * 100)}%`
    }

    if (this.hasZoomOutButtonTarget) {
      this.zoomOutButtonTarget.disabled = this.zoom <= this.minZoom
    }

    if (this.hasZoomInButtonTarget) {
      this.zoomInButtonTarget.disabled = this.zoom >= this.maxZoom
    }
  }
}
