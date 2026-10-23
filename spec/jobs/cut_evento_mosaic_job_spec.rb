require 'rails_helper'
require 'vips'

RSpec.describe CutEventoMosaicJob do
  describe '#generate_points_preview' do
    let(:work_dir) { Pathname.new(Dir.mktmpdir) }
    let(:source_path) { work_dir.join('mosaic.jpg') }

    before do
      Vips::Image.black(200, 100, bands: 3).write_to_file(source_path.to_s)
      allow(MosaicStorage).to receive(:ensure_event_dir).and_return(work_dir)
      allow(MosaicStorage).to receive(:url_for_absolute_path) { |path| "/mosaics/#{File.basename(path)}" }
    end

    after { FileUtils.rm_rf(work_dir) }

    it 'desenha os pontos em azul numa copia do mosaico' do
      url = described_class.new.send(:generate_points_preview, evento_id: 1, pasta_nome: '18h', source_path: source_path.to_s, points: [[50, 50]])

      expect(url).to start_with('/mosaics/points_')

      annotated = Vips::Image.new_from_file(work_dir.join(File.basename(url)).to_s)
      red, green, blue = annotated.getpoint(50, 50)
      expect(blue).to be > 200
      expect(red).to be < 80
      expect(green).to be_between(100, 190)
      expect(annotated.getpoint(150, 50).max).to be < 20
    end
  end
end
