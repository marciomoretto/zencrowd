require 'rails_helper'

RSpec.describe 'CrowdCountingP2PNet' do
  describe '.annotate' do
    it 'processa uma fixture e retorna uma estimativa de cabecas' do
      fixture_path = Rails.root.join('spec/fixtures/files/sample2.jpg')
      output_path = Rails.root.join('tmp/p2pnet_annotated_test.jpg')

      expect(File.exist?(fixture_path)).to be(true)

      result = begin
        CrowdCountingP2PNet.annotate(
          image_path: fixture_path.to_s,
          output_path: output_path.to_s,
          threshold: 0.5,
          device: ENV.fetch('P2PNET_DEVICE', 'cpu')
        )
      rescue Errno::ENOENT => e
        skip("Runtime do P2PNet indisponivel: #{e.message}. Instale Python 3 e dependencias Python da gem.")
      rescue CrowdCountingP2PNet::InvalidImageError => e
        skip("Runtime do P2PNet indisponivel: #{e.message}")
      rescue CrowdCountingP2PNet::InferenceError => e
        skip("Dependencias Python do P2PNet ausentes ou incompletas: #{e.message.lines.first.to_s.strip}") if missing_python_dependencies?(e.message)

        raise
      end

      expect(result.count).to be_a(Integer)
      expect(result.count).to be >= 0
      expect(result.points).to be_a(Array)
      expect(result.annotated_image_path).to be_present
      expect(File.exist?(result.annotated_image_path)).to be(true)
    ensure
      File.delete(output_path) if output_path && File.exist?(output_path)
    end
  end

  def missing_python_dependencies?(message)
    text = message.to_s.downcase

    [
      'modulenotfounderror',
      'no module named',
      'python3',
      'torch',
      'torchvision',
      'opencv',
      'numpy',
      'scipy'
    ].any? { |fragment| text.include?(fragment) }
  end
end
