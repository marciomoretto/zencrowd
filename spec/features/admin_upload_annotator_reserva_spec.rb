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
    click_link 'Upload de Imagem'
    attach_file('Arquivo', Rails.root.join('spec/fixtures/files/test_image.png'))
    fill_in 'Valor da Tarefa', with: '7.50'
    click_button 'Enviar'
    expect(page).to have_content('Imagem enviada com sucesso')

    # Annotator faz login e reserva
    logout
    login_as(annotator)
    click_link 'Imagens Disponíveis'
    expect(page).to have_content('test_image.png')
    click_button 'Reservar'
    expect(page).to have_content('Imagem reservada com sucesso!')
    expect(page).to have_content('Minha Imagem Reservada')
    expect(page).to have_content('test_image.png')
    expect(page).to have_content('Reservada')
  end
end
