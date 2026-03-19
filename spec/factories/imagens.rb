require 'stringio'

FactoryBot.define do
  factory :imagem do
    data_hora { Time.current }
    gps_location { '-23.550520,-46.633308' }
    cidade { 'Sao Paulo' }
    local { 'Avenida Paulista' }
    nome_do_evento { nil }
    posicao { nil }

    after(:build) do |imagem|
      next if imagem.arquivo.attached?

      fixture_path = Rails.root.join('spec/fixtures/files/sample.jpg')
      imagem.arquivo.attach(
        io: StringIO.new(File.binread(fixture_path)),
        filename: 'sample.jpg',
        content_type: 'image/jpeg'
      )
    end
  end
end
