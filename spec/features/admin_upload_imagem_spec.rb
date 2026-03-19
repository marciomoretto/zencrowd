require 'rails_helper'

RSpec.describe 'Admin faz upload de imagem', type: :feature do
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

  scenario 'admin deleta imagem pelo show' do
    imagem = create(:imagem)

    login_as_admin
    visit imagem_path(imagem)

    click_button 'Deletar'

    expect(page).to have_content('Imagem removida com sucesso!')
    expect(page).to have_current_path(new_imagem_path)
    expect(Imagem.exists?(imagem.id)).to be(false)
  end

  scenario 'admin corta imagem e gera tiles associados' do
    imagem = create(:imagem)

    login_as_admin
    visit imagem_path(imagem)

    click_button 'Cortar'

    imagem.reload

    expect(page).to have_content('Imagem cortada com sucesso!')
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

    expect(page).to have_content('Imagem cortada com sucesso!')
    expect(imagem.tiles.count).to eq(1)
    expect(imagem.tiles.first.id).not_to eq(old_tile.id)
    expect(Tile.exists?(old_tile.id)).to be(false)
  end
end
