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

    click_link 'Tiles Disponíveis'
    expect(page).to have_content('Tiles Disponíveis para Anotação')
    expect(page).to have_content('imagem1.png')
    within("#tile-row-#{image.id}") do
      click_button 'Reservar'
    end

    expect(page).to have_content('Tile reservado com sucesso!')
    expect(page).to have_content('Meu Tile Reservado')
    expect(page).to have_content('Editor de Pontos (ZenPlot)')
    expect(page).to have_css('[data-wpd-app]')
  end
end
