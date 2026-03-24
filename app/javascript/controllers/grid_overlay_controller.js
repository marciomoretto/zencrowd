import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["cell", "selectionLabel", "overlay", "counts", "rowsInput", "colsInput", "overlayToggleButton"]
  static values = { gridAssociated: Boolean, pieceCounts: Object }

  connect() {
    const { maxRows, maxCols } = this.maxBounds()
    const initialRows = this.hasRowsInputTarget ? this.parseCoordinate(this.rowsInputTarget.value, 1) : 1
    const initialCols = this.hasColsInputTarget ? this.parseCoordinate(this.colsInputTarget.value, 1) : 1

    this.selectedRows = Math.min(maxRows, Math.max(1, initialRows))
    this.selectedCols = Math.min(maxCols, Math.max(1, initialCols))
    this.gridVisible = this.gridAssociatedValue

    this.applySelection(this.selectedRows, this.selectedCols)
    this.applyOverlayVisibility()
    this.updateOverlayToggleButton()
  }

  toggleOverlay(event) {
    event.preventDefault()
    if (!this.gridAssociatedValue) return

    this.gridVisible = !this.gridVisible
    this.applyOverlayVisibility()
    this.updateOverlayToggleButton()
  }

  hoverCell(event) {
    const { row, col } = this.extractCoordinates(event.currentTarget)
    this.previewSelection(row, col)
  }

  selectCell(event) {
    event.preventDefault()

    const { row, col } = this.extractCoordinates(event.currentTarget)
    this.selectedRows = row
    this.selectedCols = col
    this.applySelection(row, col)
  }

  restoreSelection() {
    this.applySelection(this.selectedRows, this.selectedCols)
  }

  previewSelection(rows, cols) {
    this.paintPicker(rows, cols)
    this.updateLabel(rows, cols)
    this.paintOverlay(rows, cols)
    this.paintCounts(rows, cols)
  }

  applySelection(rows, cols) {
    this.paintPicker(rows, cols)
    this.updateLabel(rows, cols)
    this.updateInputs(rows, cols)
    this.paintOverlay(rows, cols)
    this.paintCounts(rows, cols)
  }

  extractCoordinates(element) {
    return {
      row: this.parseCoordinate(element.dataset.row, 1),
      col: this.parseCoordinate(element.dataset.col, 1)
    }
  }

  parseCoordinate(value, fallback) {
    const parsed = Number.parseInt(value || "", 10)
    return Number.isNaN(parsed) ? fallback : parsed
  }

  maxBounds() {
    if (!this.hasCellTarget) {
      return { maxRows: 1, maxCols: 1 }
    }

    const rows = this.cellTargets.map((cell) => this.extractCoordinates(cell).row)
    const cols = this.cellTargets.map((cell) => this.extractCoordinates(cell).col)

    const maxRows = rows.length > 0 ? Math.max(...rows) : 1
    const maxCols = cols.length > 0 ? Math.max(...cols) : 1

    return { maxRows, maxCols }
  }

  paintPicker(rows, cols) {
    this.cellTargets.forEach((cell) => {
      const { row, col } = this.extractCoordinates(cell)
      const isSelected = row <= rows && col <= cols
      const isAnchor = row === rows && col === cols

      cell.classList.toggle("is-selected", isSelected)
      cell.classList.toggle("is-anchor", isAnchor)
    })
  }

  updateLabel(rows, cols) {
    if (!this.hasSelectionLabelTarget) return

    this.selectionLabelTarget.textContent = `${rows}x${cols}`
  }

  updateInputs(rows, cols) {
    if (this.hasRowsInputTarget) this.rowsInputTarget.value = rows
    if (this.hasColsInputTarget) this.colsInputTarget.value = cols
  }

  paintOverlay(rows, cols) {
    if (!this.hasOverlayTarget) return

    const lineColor = "rgba(255, 255, 255, 0.9)"
    const lineHalfThicknessPx = 1.5
    const gradients = []

    for (let col = 1; col < cols; col += 1) {
      const position = ((col / cols) * 100).toFixed(4)
      gradients.push(
        `linear-gradient(to right, transparent calc(${position}% - ${lineHalfThicknessPx}px), ${lineColor} calc(${position}% - ${lineHalfThicknessPx}px), ${lineColor} calc(${position}% + ${lineHalfThicknessPx}px), transparent calc(${position}% + ${lineHalfThicknessPx}px))`
      )
    }

    for (let row = 1; row < rows; row += 1) {
      const position = ((row / rows) * 100).toFixed(4)
      gradients.push(
        `linear-gradient(to bottom, transparent calc(${position}% - ${lineHalfThicknessPx}px), ${lineColor} calc(${position}% - ${lineHalfThicknessPx}px), ${lineColor} calc(${position}% + ${lineHalfThicknessPx}px), transparent calc(${position}% + ${lineHalfThicknessPx}px))`
      )
    }

    this.overlayTarget.style.backgroundImage = gradients.length > 0 ? gradients.join(",") : "none"
  }

  applyOverlayVisibility() {
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.toggle("d-none", !this.gridVisible)
    }

    if (this.hasCountsTarget) {
      this.countsTarget.classList.toggle("d-none", !this.gridVisible)
    }
  }

  updateOverlayToggleButton() {
    if (!this.hasOverlayToggleButtonTarget) return

    this.overlayToggleButtonTarget.disabled = !this.gridAssociatedValue
    this.overlayToggleButtonTarget.textContent = this.gridVisible ? "Grid: On" : "Grid: Off"
  }

  paintCounts(rows, cols) {
    if (!this.hasCountsTarget) return

    const labels = []
    for (let row = 1; row <= rows; row += 1) {
      for (let col = 1; col <= cols; col += 1) {
        const key = `${row}-${col}`
        const value = this.pieceCountsValue?.[key]
        if (value === undefined || value === null) continue

        const left = (((col - 0.5) / cols) * 100).toFixed(4)
        const top = (((row - 0.5) / rows) * 100).toFixed(4)

        labels.push(
          `<span class="grid-overlay-count-badge" style="left:${left}%;top:${top}%">${value}</span>`
        )
      }
    }

    this.countsTarget.innerHTML = labels.join("")
  }
}
