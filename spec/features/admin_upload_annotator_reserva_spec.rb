require 'rails_helper'

RSpec.describe 'Admin faz upload e annotator reserva', type: :feature do
  let!(:admin) { create(:user, :admin) }
  let!(:annotator) { create(:user, :annotator) }

  def login_as(user)
    visit login_path
    fill_in 'E-mail', with: user.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'
  end

  def logout
    page.driver.submit :delete, logout_path, {}
  end

  scenario 'Admin faz upload de imagem, annotator reserva e vê tarefa' do
    # Admin faz login
    login_as(admin)
    click_link 'Upload de Tile'
    attach_file('Arquivo', Rails.root.join('spec/fixtures/files/test_image.png'))
    fill_in 'Valor da Tarefa', with: '7.50'
    click_button 'Enviar'
    expect(page).to have_content('Tile enviado com sucesso')
    uploaded_tile = Tile.order(:id).last
    expect(uploaded_tile.original_filename).to eq('test_image.png')

    # Annotator faz login e reserva
    logout
    login_as(annotator)
    click_link 'Tiles Disponíveis'
    expect(page).to have_content('test_image.png')
    within("#tile-row-#{uploaded_tile.id}") do
      click_button 'Reservar'
    end
    expect(page).to have_content('Tile reservado com sucesso!')
    expect(page).to have_content('Meu Tile Reservado')
    expect(page).to have_content('test_image.png')
  end
end
