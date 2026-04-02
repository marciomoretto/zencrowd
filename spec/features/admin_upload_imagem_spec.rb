require 'rails_helper'
require 'exifr/jpeg'

RSpec.describe 'Admin faz upload de imagem', type: :feature do
  include ActiveJob::TestHelper

  let!(:admin) { create(:user, :admin) }

  def login_as_admin
    visit login_path
    fill_in 'E-mail', with: admin.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'
  end

  scenario 'admin envia apenas arquivo e e redirecionado para show da imagem' do
    login_as_admin

    visit new_imagem_path
    expect(page).to have_current_path(new_imagem_path)

    attach_file('imagem_arquivo', Rails.root.join('spec/fixtures/files/sample.jpg'))
    click_button 'Enviar'

    imagem = Imagem.order(:id).last

    expect(page).to have_content('Imagem enviada com sucesso!')
    expect(page).to have_current_path(imagem_path(imagem))
    expect(page).to have_content('Nao informada')
    expect(page).to have_content('Nao informado')
    expect(page).to have_content('Nenhum tile associado a esta imagem.')

    expect(imagem.gps_location).to eq('0.000000,0.000000')
    expect(imagem.cidade).to eq('Nao informada')
    expect(imagem.local).to eq('Nao informado')
    expect(imagem.data_hora).to be_present
    expect(imagem.exif_metadata).to be_a(Hash)
    expect(imagem.xmp_metadata).to be_a(Hash)
    expect(imagem.tiles).to be_empty
  end

  scenario 'admin envia fixture com GPS e geocoding preenche cidade e local' do
    fixture_path = Rails.root.join('spec/fixtures/files/test_image.jpg')
    latitude = -23.561414
    longitude = -46.655881

    allow(ImagemMetadataExtractor).to receive(:extract).and_return(
      {
        exif: { 'gps_latitude' => latitude, 'gps_longitude' => longitude },
        xmp: {},
        normalized: {
          gps_location: format('%.6f,%.6f', latitude, longitude),
          cidade: 'Sao Paulo',
          local: 'Avenida Paulista',
          data_hora: Time.current.change(sec: 0)
        }
      }
    )
    allow(ProcessUploadedImagemJob).to receive(:perform_later) do |imagem_id, options|
      ProcessUploadedImagemJob.perform_now(imagem_id, options)
    end

    login_as_admin

    visit new_imagem_path
    expect(page).to have_current_path(new_imagem_path)

    attach_file('imagem_arquivo', fixture_path)
    click_button 'Enviar'

    imagem = Imagem.order(:id).last

    expect(page).to have_content('Imagem enviada com sucesso!')
    expect(page).to have_current_path(imagem_path(imagem))
    expect(page).to have_content('Sao Paulo')
    expect(page).to have_content('Avenida Paulista')

    expect(ImagemMetadataExtractor).to have_received(:extract)

    expect(imagem.gps_location).to eq(format('%.6f,%.6f', latitude, longitude))
    expect(imagem.cidade).to eq('Sao Paulo')
    expect(imagem.local).to eq('Avenida Paulista')
    expect(imagem.exif_metadata['gps_latitude']).to be_within(0.000001).of(latitude)
    expect(imagem.exif_metadata['gps_longitude']).to be_within(0.000001).of(longitude)
  end

  scenario 'admin deleta imagem pelo show' do
    imagem = create(:imagem)

    login_as_admin
    visit imagem_path(imagem)

    click_button 'Deletar'

    expect(page).to have_content('Imagem nao encontrada.')
    expect(page).to have_current_path(new_imagem_path)
    expect(Imagem.exists?(imagem.id)).to be(false)
  end

  scenario 'admin visualiza status zenital no show da imagem' do
    AppSetting.find_or_initialize_by(key: AppSetting::KEY_ZENITH_TOLERANCE_DEGREES).tap do |setting|
      setting.value = '2'
      setting.save!
    end
    imagem = create(:imagem, xmp_metadata: { 'drone-dji:GimbalPitchDegree' => '-89.20' })

    login_as_admin
    visit imagem_path(imagem)

    expect(page).to have_content('Zenital')
    expect(page).to have_content('Sim')
    expect(page).to have_css('.badge.text-bg-success[title*="Pitch do gimbal: -89.20 deg"]')
    expect(page).to have_css('.badge.text-bg-success[title*="Tolerancia: +/-2 deg"]')
  end

  scenario 'admin nao visualiza grid e botao cortar para imagem nao zenital' do
    AppSetting.find_or_initialize_by(key: AppSetting::KEY_ZENITH_TOLERANCE_DEGREES).tap do |setting|
      setting.value = '2'
      setting.save!
    end
    imagem = create(:imagem, xmp_metadata: { 'drone-dji:GimbalPitchDegree' => '-70.00' })

    login_as_admin
    visit imagem_path(imagem)

    expect(page).to have_content('Zenital')
    expect(page).to have_content('Nao')
    expect(page).not_to have_content('Seletor de Grade')
    expect(page).not_to have_button('Cortar')
  end

  scenario 'admin corta imagem e gera tiles associados' do
    imagem = create(:imagem)

    login_as_admin
    visit imagem_path(imagem)

    click_button 'Cortar'

    imagem.reload

    expect(page).to have_content('Corte concluído.')
    expect(imagem.tiles.count).to eq(1)
    expect(page).not_to have_content('Nenhum tile associado a esta imagem.')
  end

  scenario 'admin corta novamente e substitui tiles antigos associados' do
    imagem = create(:imagem)
    old_tile = create(:tile, uploader: admin)
    create(:imagem_tile, imagem: imagem, tile: old_tile)

    login_as_admin
    visit imagem_path(imagem)

    click_button 'Cortar'

    imagem.reload

    expect(page).to have_content('Corte concluído.')
    expect(imagem.tiles.count).to eq(1)
    expect(imagem.tiles.first.id).not_to eq(old_tile.id)
    expect(Tile.exists?(old_tile.id)).to be(false)
  end

  scenario 'admin visualiza e edita evento associado com autocomplete inline no show' do
    evento_antigo = create(:evento, nome: 'Manifestacao A')
    evento_novo = create(:evento, nome: 'Manifestacao B')
    imagem = create(:imagem, evento: evento_antigo)

    login_as_admin
    visit imagem_path(imagem)

    expect(page).to have_content('Evento')
    expect(page).to have_content('Manifestacao A')

    find("[data-evento-autocomplete-inline-target='display']").click

    fill_in 'imagem_evento_autocomplete', with: "Manifestacao B - ##{evento_novo.id}"
    click_button 'Salvar evento'

    expect(page).to have_content('Evento da imagem atualizado com sucesso.')
    expect(page).to have_content('Manifestacao B')

    imagem.reload
    expect(imagem.evento).to eq(evento_novo)
  end
end
