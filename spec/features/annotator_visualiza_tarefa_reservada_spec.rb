require 'rails_helper'

RSpec.describe 'Annotator visualiza tarefa reservada', type: :feature do
  let!(:admin) { create(:user, :admin) }
  let!(:annotator) { create(:user, :annotator) }
  let!(:outra_annotator) { create(:user, :annotator) }
  let!(:image) { create(:image, uploader: admin, status: :reserved, reserver: annotator, original_filename: 'imagem_tarefa.jpg', task_value: 12.5, storage_path: Rails.root.join('spec/fixtures/files/test_image.jpg')) }

  scenario 'Annotator vê sua imagem reservada com dados e preview' do
    visit '/login'
    fill_in 'E-mail', with: annotator.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'
    click_link 'Minha Tarefa'
    expect(page).to have_content('Meu Tile Reservado')
    expect(page).to have_content(image.id)
    expect(page).to have_content('imagem_tarefa.jpg')
    expect(page).to have_content('12,50')
    expect(page).to have_css('img.img-thumbnail')
  end

  scenario 'Annotator sem imagem reservada vê mensagem e link' do
    visit '/login'
    fill_in 'E-mail', with: outra_annotator.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'
    click_link 'Minha Tarefa'
    expect(page).to have_content('Nenhuma tarefa reservada')
    expect(page).to have_link('Ver tiles disponíveis')
  end

  scenario 'Annotator não acessa tarefa de outro usuário' do
    visit '/login'
    fill_in 'E-mail', with: outra_annotator.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'
    visit my_task_path
    expect(page).not_to have_content(image.id)
    expect(page).to have_content('Nenhuma tarefa reservada')
  end
end
