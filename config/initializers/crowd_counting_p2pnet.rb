# frozen_string_literal: true

if defined?(CrowdCountingP2PNet)
  CrowdCountingP2PNet.configure do |config|
    config.python_bin = ENV.fetch('P2PNET_PYTHON_BIN', config.python_bin)

    custom_weight_path = ENV['P2PNET_WEIGHT_PATH'].to_s
    config.weight_path = custom_weight_path if custom_weight_path.present?
  end
end
