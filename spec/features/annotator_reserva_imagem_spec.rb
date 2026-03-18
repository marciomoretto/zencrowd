require 'rails_helper'

RSpec.describe 'Annotator reserva imagem e vê tarefa', type: :feature do
  let!(:admin) { create(:user, :admin) }
  let!(:annotator) { create(:user, :annotator) }
  let!(:image) { create(:image, uploader: admin, status: :available, original_filename: 'imagem1.png', task_value: 5.0) }

  scenario 'Annotator faz login, reserva imagem e vê sua tarefa' do
    visit '/login'
    fill_in 'E-mail', with: annotator.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'

    click_link 'Imagens Disponíveis'
    expect(page).to have_content('Imagens Disponíveis para Anotação')
    expect(page).to have_content('imagem1.png')
    click_button 'Reservar'

    expect(page).to have_content('Imagem reservada com sucesso!')
    expect(page).to have_content('Minha Imagem Reservada')
    expect(page).to have_content('imagem1.png')
    expect(page).to have_content('Reservada')
  end
end
