require 'rails_helper'

RSpec.describe 'Admin cria tile com contagem de cabecas', type: :feature do
  let!(:admin) { create(:user, :admin) }

  def login_as(user)
    visit login_path
    fill_in 'E-mail', with: user.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'
  end

  scenario 'admin cria tile e salva contagem de cabecas no atributo head_count' do
    fake_result = instance_double('CrowdCountingP2PNet::Result', count: 23)
    allow(CrowdCountingP2PNet).to receive(:annotate).and_return(fake_result)

    login_as(admin)

    visit new_tile_path
    attach_file 'Arquivo do Tile', Rails.root.join('spec/fixtures/files/sample2.jpg')
    click_button 'Enviar'

    tile = Tile.order(:id).last

    expect(page).to have_content('Tile enviado com sucesso!')
    expect(tile.head_count).to eq(23)
  end

  scenario 'admin recebe aviso quando inferencia quebra por OOM' do
    allow(CrowdCountingP2PNet).to receive(:annotate)
      .and_raise(CrowdCountingP2PNet::InferenceError, 'Killed')

    login_as(admin)

    visit new_tile_path
    attach_file 'Arquivo do Tile', Rails.root.join('spec/fixtures/files/sample2.jpg')
    click_button 'Enviar'

    tile = Tile.order(:id).last

    expect(page).to have_content('Tile enviado com sucesso!')
    expect(page).to have_content('Imagem muito grande, tente quebrar em pedaços menores.')
    expect(tile.head_count).to be_nil
  end
end
