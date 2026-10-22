require 'rails_helper'
require 'securerandom'

RSpec.describe MosaicTempGridCutter do
  let(:test_dir) { Rails.root.join('tmp', "mosaic_cutter_spec_#{SecureRandom.hex(6)}") }
  let(:source_path) { test_dir.join('mosaico.jpg').to_s }
  let(:cutter) { described_class.new(source_path: source_path, evento_id: 1, pasta_nome: 'Voo') }

  before do
    require 'vips'
    FileUtils.mkdir_p(test_dir)
    # Janelas de 1000x1000 => cores de 800x800
    allow(P2pnetInferenceSettings).to receive(:tile_max_pixels).and_return(1_000_000)
    allow(P2pnetInferenceSettings).to receive(:tile_overlap_px).and_return(100)
  end

  after { FileUtils.rm_rf(test_dir) }

  def write_mosaic(width, height, brightness)
    (Vips::Image.black(width, height, bands: 3) + brightness).cast(:uchar).write_to_file(source_path)
  end

  def p2pnet_result(points, resized_size)
    CrowdCountingP2PNet::Result.new(
      count: points.size,
      annotated_image_path: '',
      points: points,
      raw_payload: { 'resized_width' => resized_size[0], 'resized_height' => resized_size[1] }
    )
  end

  it 'conta cada pessoa uma unica vez, inclusive na sobreposicao, mapeando os pontos para o mosaico' do
    write_mosaic(2400, 1200, 120)
    plan = MosaicTilePlanner.plan(width: 2400, height: 1200)
    expect([plan.rows, plan.cols]).to eq([2, 3])

    # (800, 600) fica na divisa entre cores e dentro de varias janelas
    people = [[10, 10], [790, 400], [810, 400], [800, 600], [1500, 300], [1590, 1190], [2399, 1199]]
    call_index = -1

    allow(CrowdCountingP2PNet).to receive(:annotate) do
      window = plan.tiles[call_index += 1].window
      # O P2PNet devolve pontos na imagem redimensionada (metade do tamanho, neste teste).
      local_points = people.filter_map do |x, y|
        [(x - window.x) * 0.5, (y - window.y) * 0.5] if window.contains?(x, y)
      end

      p2pnet_result(local_points, [window.width / 2, window.height / 2])
    end

    result = cutter.call

    expect(result.success?).to be(true)
    expect(result.total_heads).to eq(people.size)
    expect(result.piece_counts.sum { |piece| piece[:estimated_heads] }).to eq(people.size)
    expect(result.points.map { |x, y| [x.round, y.round] }).to match_array(people)
    expect([result.rows, result.cols]).to eq([2, 3])
  end

  it 'nao roda inferencia em mosaico sem dados (preto)' do
    write_mosaic(1500, 900, 0)
    expect(CrowdCountingP2PNet).not_to receive(:annotate)

    result = cutter.call

    expect(result.success?).to be(true)
    expect(result.total_heads).to eq(0)
  end

  it 'subdivide o tile em 4 quando a inferencia estoura memoria' do
    write_mosaic(700, 700, 120)
    calls = 0

    allow(CrowdCountingP2PNet).to receive(:annotate) do
      calls += 1
      raise CrowdCountingP2PNet::InferenceError, 'processo finalizado (exit 137)' if calls == 1

      p2pnet_result([], [128, 128])
    end

    result = cutter.call

    expect(result.success?).to be(true)
    expect(calls).to eq(5)
    expect(result.piece_counts.size).to eq(1)
  end

  context 'com um backend remoto (ex.: Cloud Run)' do
    let(:backend) do
      Class.new do
        attr_reader :rounds, :prepared_path, :cleaned

        def initialize
          @rounds = []
          @cleaned = false
        end

        def prepare(source_path:)
          @prepared_path = source_path
        end

        # A primeira janela de cada rodada 0 estoura memoria; as subdivididas dao 1 pessoa no centro do core.
        def infer(items)
          @rounds << items.map(&:id)
          items.each do |item|
            if item.id.include?('-d0-')
              yield item, MosaicCounting::Outcome.new(status: :oom)
            else
              window = item.window
              yield item, MosaicCounting::Outcome.new(
                status: :ok,
                points: [[window.width / 2.0, window.height / 2.0]],
                resized_width: window.width,
                resized_height: window.height
              )
            end
          end
        end

        def cleanup
          @cleaned = true
        end
      end.new
    end

    it 're-despacha janelas sem memoria subdivididas em 4 e fecha o progresso por tile' do
      write_mosaic(700, 700, 120)
      allow(MosaicCounting).to receive(:build).and_return(backend)
      progress = []

      result = cutter.call(progress_callback: ->(payload) { progress << payload[:processed_count] })

      expect(result.success?).to be(true)
      expect(backend.rounds.map(&:size)).to eq([1, 4])
      expect(backend.prepared_path).to eq(source_path)
      expect(backend.cleaned).to be(true)
      expect(result.piece_counts.size).to eq(1)
      expect(result.total_heads).to eq(4)
      expect(progress.first).to eq(0)
      expect(progress.last).to eq(1)
    end

    it 'devolve erro claro quando o backend falha' do
      write_mosaic(700, 700, 120)
      allow(backend).to receive(:infer).and_raise(MosaicCounting::BackendError, 'Cloud Run indisponivel')
      allow(MosaicCounting).to receive(:build).and_return(backend)

      result = cutter.call

      expect(result.success?).to be(false)
      expect(result.error).to eq('Cloud Run indisponivel')
      expect(backend.cleaned).to be(true)
    end
  end

  it 'falha quando o arquivo do mosaico nao existe' do
    result = described_class.new(source_path: '/nao/existe.jpg', evento_id: 1, pasta_nome: 'Voo').call

    expect(result.success?).to be(false)
    expect(result.error).to be_present
  end
end
