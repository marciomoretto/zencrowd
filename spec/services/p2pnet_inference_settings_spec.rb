require 'rails_helper'

RSpec.describe P2pnetInferenceSettings do
  def with_env(values)
    stub_const('ENV', ENV.to_hash.merge(values))
  end

  it 'usa os filtros de textura e de verde por padrao' do
    with_env('P2PNET_MIN_TEXTURE' => nil, 'P2PNET_MAX_GREEN_FRACTION' => nil)

    expect(described_class.min_texture).to eq(12.0)
    expect(described_class.max_green_fraction).to eq(0.6)
  end

  it 'aceita 0 para desligar e volta ao padrao com valores invalidos' do
    with_env('P2PNET_MIN_TEXTURE' => '0', 'P2PNET_MAX_GREEN_FRACTION' => 'abc')

    expect(described_class.min_texture).to eq(0.0)
    expect(described_class.max_green_fraction).to eq(0.6)

    with_env('P2PNET_MIN_TEXTURE' => '-3', 'P2PNET_MAX_GREEN_FRACTION' => '0.75')

    expect(described_class.min_texture).to eq(12.0)
    expect(described_class.max_green_fraction).to eq(0.75)
  end
end
