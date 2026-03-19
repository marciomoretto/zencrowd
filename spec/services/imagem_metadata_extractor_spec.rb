require 'rails_helper'

RSpec.describe ImagemMetadataExtractor do
  describe '.normalized_attributes' do
    let(:exif_data) do
      {
        'gps_latitude' => -23.55052,
        'gps_longitude' => -46.633308
      }
    end

    it 'preenche cidade e local usando geocoder com coordenadas GPS' do
      geocoder_result = instance_double(
        'GeocoderResult',
        city: 'Sao Paulo',
        address: 'Avenida Paulista, Bela Vista',
        data: {
          'address' => {
            'city' => 'Sao Paulo',
            'road' => 'Avenida Paulista',
            'house_number' => '1578'
          }
        }
      )

      allow(Geocoder).to receive(:search).with([-23.55052, -46.633308]).and_return([geocoder_result])

      normalized = described_class.send(:normalized_attributes, exif_data, {})

      expect(normalized[:gps_location]).to eq('-23.550520,-46.633308')
      expect(normalized[:cidade]).to eq('Sao Paulo')
      expect(normalized[:local]).to eq('Avenida Paulista 1578')
    end

    it 'nao consulta geocoder para coordenada padrao 0,0' do
      allow(Geocoder).to receive(:search)

      normalized = described_class.send(
        :normalized_attributes,
        { 'gps_latitude' => 0.0, 'gps_longitude' => 0.0 },
        {}
      )

      expect(Geocoder).not_to have_received(:search)
      expect(normalized[:cidade]).to eq('Nao informada')
      expect(normalized[:local]).to eq('Nao informado')
    end

    it 'usa fallback quando geocoder nao retorna resultado' do
      allow(Geocoder).to receive(:search).and_return([])

      normalized = described_class.send(:normalized_attributes, exif_data, {})

      expect(normalized[:cidade]).to eq('Nao informada')
      expect(normalized[:local]).to eq('Nao informado')
    end
  end
end
