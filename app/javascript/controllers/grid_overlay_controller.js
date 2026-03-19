import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["cell", "selectionLabel", "overlay", "rowsInput", "colsInput"]

  connect() {
    this.selectedRows = 1
    this.selectedCols = 1
    this.applySelection(this.selectedRows, this.selectedCols)
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
  }

  applySelection(rows, cols) {
    this.paintPicker(rows, cols)
    this.updateLabel(rows, cols)
    this.updateInputs(rows, cols)
    this.paintOverlay(rows, cols)
  }

  extractCoordinates(element) {
    return {
      row: Number.parseInt(element.dataset.row || "1", 10),
      col: Number.parseInt(element.dataset.col || "1", 10)
    }
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
}
