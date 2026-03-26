require 'rails_helper'

RSpec.describe ImagemMetadataExtractor do
  describe '.extract' do
    it 'extrai coordenadas GPS da fixture e usa geocoding para definir cidade' do
      fixture_path = Rails.root.join('spec/fixtures/files/test_image.jpg')
      exif_image = EXIFR::JPEG.new(fixture_path.to_s)
      gps = exif_image.respond_to?(:gps) ? exif_image.gps : nil
      latitude = gps&.respond_to?(:latitude) ? gps.latitude&.to_f : nil
      longitude = gps&.respond_to?(:longitude) ? gps.longitude&.to_f : nil

      if latitude.nil? || longitude.nil?
        dms_to_decimal = proc do |dms, ref|
          next nil unless dms.is_a?(Array) && dms.size >= 3

          degrees, minutes, seconds = dms.first(3).map(&:to_f)
          decimal = degrees + (minutes / 60.0) + (seconds / 3600.0)
          %w[S W].include?(ref.to_s.upcase) ? -decimal : decimal
        end

        exif_hash = exif_image.exif&.to_hash || {}
        latitude ||= dms_to_decimal.call(exif_hash[:gps_latitude], exif_hash[:gps_latitude_ref])
        longitude ||= dms_to_decimal.call(exif_hash[:gps_longitude], exif_hash[:gps_longitude_ref])
      end

      expect(latitude).not_to be_nil
      expect(longitude).not_to be_nil

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

      allow(Geocoder).to receive(:search).and_return([geocoder_result])

      File.open(fixture_path, 'rb') do |file|
        extracted = described_class.extract(file)

        expect(extracted[:exif]['gps_latitude']).to be_within(0.000001).of(latitude)
        expect(extracted[:exif]['gps_longitude']).to be_within(0.000001).of(longitude)
        expect(Geocoder).to have_received(:search).with([
          be_within(0.000001).of(latitude),
          be_within(0.000001).of(longitude)
        ])
        expect(extracted[:normalized][:cidade]).to eq('Sao Paulo')
        expect(extracted[:normalized][:gps_location]).to eq(format('%.6f,%.6f', latitude, longitude))
      end
    end
  end

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
      expect(normalized[:local]).to eq('Avenida Paulista')
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

    it 'prioriza data original dos metadados em vez da data generica' do
      normalized = described_class.send(
        :normalized_attributes,
        {
          'date_time' => '2026-03-19T18:10:00Z',
          'date_time_original' => '2024-01-05T12:34:56Z'
        },
        {}
      )

      expect(normalized[:data_hora].utc).to eq(Time.parse('2024-01-05T12:34:56Z'))
    end

    it 'interpreta formato EXIF de data com separador por dois-pontos' do
      normalized = described_class.send(
        :normalized_attributes,
        { 'date_time_original' => '2025:12:07 15:08:21' },
        {}
      )

      expected = Time.zone ? Time.zone.parse('2025-12-07 15:08:21') : Time.parse('2025-12-07 15:08:21')
      expect(normalized[:data_hora]).to eq(expected)
    end
  end
end
