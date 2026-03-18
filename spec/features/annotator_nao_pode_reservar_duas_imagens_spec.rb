require 'rails_helper'

RSpec.describe 'Annotator não pode reservar duas imagens', type: :feature do
  let!(:admin) { create(:user, :admin) }
  let!(:annotator) { create(:user, :annotator) }
  let!(:image1) { create(:image, uploader: admin, status: :available, original_filename: 'imagem1.png', task_value: 5.0) }
  let!(:image2) { create(:image, uploader: admin, status: :available, original_filename: 'imagem2.png', task_value: 7.0) }

  scenario 'Annotator tenta reservar duas imagens e é bloqueado' do
    visit '/login'
    fill_in 'E-mail', with: annotator.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'

    click_link 'Imagens Disponíveis'
    expect(page).to have_content('imagem1.png')
    expect(page).to have_content('imagem2.png')
    click_button 'Reservar', match: :first

    expect(page).to have_content('Imagem reservada com sucesso!')
    expect(page).to have_content('Minha Imagem Reservada')
    expect(page).to have_content('imagem1.png')
    expect(page).to have_content('Reservada')

    # Tentar reservar outra imagem
    visit available_images_path
    expect(page).to have_content('Você já possui uma imagem reservada')
    expect(page).not_to have_button('Reservar')
  end
end
