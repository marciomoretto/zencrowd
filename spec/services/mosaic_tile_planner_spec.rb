require 'rails_helper'

RSpec.describe MosaicTilePlanner do
  describe '.plan' do
    it 'usa um unico tile quando o mosaico cabe no orcamento de pixels' do
      plan = described_class.plan(width: 1500, height: 1000, max_pixels: 6_000_000, overlap: 128)

      expect([plan.rows, plan.cols]).to eq([1, 1])
      tile = plan.tiles.first
      expect(tile.core.to_a).to eq([0, 0, 1500, 1000])
      expect(tile.window.to_a).to eq([0, 0, 1500, 1000])
    end

    it 'calcula o grid pela resolucao e cobre o mosaico sem lacunas nem sobreposicao nos cores' do
      plan = described_class.plan(width: 12_000, height: 7_000, max_pixels: 6_000_000, overlap: 128)

      expect(plan.cols).to eq((12_000.0 / (2449 - 256)).ceil)
      expect(plan.rows).to eq((7_000.0 / (2449 - 256)).ceil)
      expect(plan.tiles.size).to eq(plan.rows * plan.cols)
      expect(plan.tiles.sum { |tile| tile.core.width * tile.core.height }).to eq(12_000 * 7_000)

      plan.tiles.each do |tile|
        expect(tile.window.width * tile.window.height).to be <= 6_000_000
        expect(tile.window.x).to be >= 0
        expect(tile.window.right).to be <= 12_000
        expect(tile.window.bottom).to be <= 7_000
      end
    end

    it 'adiciona a margem de sobreposicao ao redor do core, limitada pelas bordas' do
      plan = described_class.plan(width: 6_000, height: 3_000, max_pixels: 4_000_000, overlap: 100)
      first = plan.tiles.first
      second = plan.tiles.find { |tile| tile.row_index == 1 && tile.col_index == 2 }

      expect(first.window.x).to eq(0)
      expect(first.window.right).to eq(first.core.right + 100)
      expect(second.window.x).to eq(second.core.x - 100)
    end

    it 'rejeita dimensoes invalidas' do
      expect { described_class.plan(width: 0, height: 10) }.to raise_error(ArgumentError)
    end
  end

  describe '.split' do
    let(:plan) { described_class.plan(width: 8_000, height: 8_000, max_pixels: 6_000_000, overlap: 128) }

    it 'divide o core em 4 partes que cobrem exatamente o core original' do
      tile = plan.tiles.first
      parts = described_class.split(tile, plan)

      expect(parts.size).to eq(4)
      expect(parts.sum { |part| part.core.width * part.core.height }).to eq(tile.core.width * tile.core.height)
      expect(parts.map { |part| [part.row_index, part.col_index] }.uniq).to eq([[tile.row_index, tile.col_index]])
    end

    it 'retorna nil quando o tile ja esta no tamanho minimo' do
      tiny = described_class::Tile.new(
        row_index: 1,
        col_index: 1,
        core: described_class::Rect.new(0, 0, 300, 300),
        window: described_class::Rect.new(0, 0, 300, 300)
      )

      expect(described_class.split(tiny, plan)).to be_nil
    end
  end
end
