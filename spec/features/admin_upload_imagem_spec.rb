require 'rails_helper'

RSpec.describe 'Admin faz upload de imagem com metadados', type: :feature do
  let!(:admin) { create(:user, :admin) }
  let!(:tile) { create(:tile, original_filename: 'tile_relacionado.png') }

  scenario 'admin envia imagem e e redirecionado para show da imagem' do
    visit login_path
    fill_in 'E-mail', with: admin.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'

    visit new_imagem_path
    expect(page).to have_current_path(new_imagem_path)

    attach_file('imagem_arquivo', Rails.root.join('spec/fixtures/files/sample.jpg'))
    fill_in 'Data e Hora', with: '2026-03-19T10:30'
    fill_in 'GPS', with: '-23.550520,-46.633308'
    fill_in 'Cidade', with: 'Sao Paulo'
    fill_in 'Local', with: 'Parque Ibirapuera'
    fill_in 'Nome do Evento', with: 'Teste de Campo'
    select 'Direita', from: 'Posicao'
    find("select[name='imagem[tile_ids][]']").find("option[value='#{tile.id}']").select_option

    click_button 'Enviar'

    imagem = Imagem.order(:id).last

    expect(page).to have_content('Imagem enviada com sucesso!')
    expect(page).to have_current_path(imagem_path(imagem))
    expect(page).to have_content('-23.550520,-46.633308')
    expect(page).to have_content('Sao Paulo')
    expect(page).to have_content('Parque Ibirapuera')
    expect(page).to have_content('Teste de Campo')
    expect(page).to have_content('Direita')
    expect(page).to have_content(tile.original_filename)

    expect(imagem.tiles).to include(tile)
  end
end
