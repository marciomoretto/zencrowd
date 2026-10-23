require 'rails_helper'
require 'securerandom'

RSpec.describe EventoMosaicGenerator do
  describe '#run_mosaic_engine! (cloud run backend)' do
    let(:generator) { described_class.new(evento: double(id: 123), pasta_param: 'Voo') }
    let(:input_dir) { Rails.root.join('tmp', "mosaic_engine_spec_input_#{SecureRandom.hex(8)}") }
    let(:output_dir) { Rails.root.join('tmp', "mosaic_engine_spec_output_#{SecureRandom.hex(8)}") }

    before do
      FileUtils.mkdir_p(input_dir)
      FileUtils.mkdir_p(output_dir)
    end

    after do
      FileUtils.rm_rf(input_dir)
      FileUtils.rm_rf(output_dir)
    end

    it 'delegates to Cloud Run when configured' do
      cloud_renderer = instance_double(MosaicRendering::CloudRun)
      allow(MosaicRendering::Settings).to receive(:cloud_run?).and_return(true)
      allow(MosaicRendering::CloudRun).to receive(:new).and_return(cloud_renderer)
      allow(cloud_renderer).to receive(:render!).and_return(output_dir.join('mosaico.jpg').to_s)

      generator.send(:run_mosaic_engine!, input_dir: input_dir, output_dir: output_dir)

      expect(cloud_renderer).to have_received(:render!).with(input_dir: input_dir, output_dir: output_dir, on_progress: kind_of(Proc))
    end
  end

  describe '#run_mosaic_engine! (local backend)' do
    let(:generator) { described_class.new(evento: double(id: 123), pasta_param: 'Voo') }
    let(:test_dir) { Rails.root.join('tmp', "mosaic_engine_spec_#{SecureRandom.hex(8)}") }
    let(:input_dir) { test_dir.join('input') }
    let(:output_dir) { test_dir.join('output') }
    let(:script_path) { Rails.root.join('lib', 'mosaico', 'mosaico_dji.py') }

    before do
      FileUtils.mkdir_p(input_dir)
      FileUtils.mkdir_p(output_dir)
      allow(MosaicRendering::Settings).to receive(:cloud_run?).and_return(false)
    end

    after do
      FileUtils.rm_rf(test_dir)
    end

    it 'runs the new DJI renderer and returns the generated mosaic path' do
      process_status = double(success?: true, exitstatus: 0)

      expect(Open3).to receive(:capture3) do |*command|
        expect(command.first).to eq(
          ENV.fetch('MOSAIC_PYTHON_BIN', ENV.fetch('P2PNET_PYTHON_BIN', 'python3'))
        )
        expect(command[1]).to eq(script_path.to_s)
        expect(command).to include(input_dir.to_s, '--output-dir', output_dir.to_s, '--overwrite', '--no-zip')

        File.write(output_dir.join('mosaico.jpg'), 'image')
        ['render complete', '', process_status]
      end

      result = generator.send(:run_mosaic_engine!, input_dir: input_dir, output_dir: output_dir)

      expect(result).to eq(output_dir.join('mosaico.jpg').to_s)
      expect(File).to exist(result)
    end

    it 'surfaces the renderer error when the process fails' do
      process_status = double(success?: false, exitstatus: 2)
      allow(Open3).to receive(:capture3).and_return(['', 'ExifTool missing', process_status])

      expect do
        generator.send(:run_mosaic_engine!, input_dir: input_dir, output_dir: output_dir)
      end.to raise_error(StandardError, /ExifTool missing/)
    end

    it 'rejects a successful process that did not create a valid mosaic' do
      process_status = double(success?: true, exitstatus: 0)
      allow(Open3).to receive(:capture3).and_return(['render complete', '', process_status])

      expect do
        generator.send(:run_mosaic_engine!, input_dir: input_dir, output_dir: output_dir)
      end.to raise_error(StandardError, /nao produziu uma imagem de saida valida/)
    end
  end
end
