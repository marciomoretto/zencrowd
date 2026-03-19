require 'rails_helper'

RSpec.describe 'Admin::Images', type: :feature do
  let!(:admin) { create(:user, :admin) }
  let!(:annotator) { create(:user, :annotator) }
  let!(:image1) { create(:image, original_filename: 'img1.jpg', status: :available, task_value: 10.0) }
  let!(:image2) { create(:image, original_filename: 'img2.png', status: :reserved, task_value: 20.0) }

  def login_as(user)
    visit login_path
    fill_in 'E-mail', with: user.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'
  end

  scenario 'admin acessa listagem de imagens' do
    login_as(admin)
    visit admin_images_path
    expect(page).to have_content('Tiles cadastrados')
    expect(page).to have_selector('table')
    expect(page).to have_content(image1.original_filename)
    expect(page).to have_content(image2.original_filename)
    expect(page).to have_content(image1.status)
    expect(page).to have_content(image2.status)
    expect(page).to have_content(image1.task_value)
    expect(page).to have_content(image2.task_value)
  end

  scenario 'annotator não acessa listagem de imagens' do
    login_as(annotator)
    visit admin_images_path
    expect(page).to have_content('Acesso restrito ao administrador')
    expect(current_path).to eq(dashboard_path)
  end

  scenario 'admin acessa tela de upload de imagens' do
    login_as(admin)
    visit new_admin_image_path
    expect(page).to have_content('Upload de Imagens')
    expect(page).to have_selector('form')
    expect(page).to have_field('images[]', type: 'file')
    expect(page).to have_field('task_value')
  end

  scenario 'annotator não acessa tela de upload' do
    login_as(annotator)
    visit new_admin_image_path
    expect(page).to have_content('Acesso restrito ao administrador')
    expect(current_path).to eq(dashboard_path)
  end

  scenario 'admin faz upload de uma imagem válida' do
    login_as(admin)
    visit new_admin_image_path
    attach_file('images[]', Rails.root.join('spec/fixtures/files/sample.jpg'))
    fill_in 'task_value', with: 42.5
    click_button 'Enviar'
    expect(page).to have_content('1 tile(s) enviado(s) com sucesso')
    expect(Image.last.task_value.to_f).to eq(42.5)
    expect(Image.last.status).to eq('available')
    expect(Image.last.original_filename).to eq('sample.jpg')
  end

  scenario 'admin faz upload de múltiplas imagens' do
    login_as(admin)
    visit new_admin_image_path
    attach_file('images[]', [Rails.root.join('spec/fixtures/files/sample.jpg'), Rails.root.join('spec/fixtures/files/sample2.jpg')])
    fill_in 'task_value', with: 15.0
    click_button 'Enviar'
    expect(page).to have_content('2 tile(s) enviado(s) com sucesso')
    expect(Image.order(:created_at).last(2).pluck(:task_value)).to all(eq(15.0))
    expect(Image.order(:created_at).last(2).pluck(:status)).to all(eq('available'))
  end

  scenario 'admin tenta enviar arquivo inválido' do
    login_as(admin)
    visit new_admin_image_path
    attach_file('images[]', Rails.root.join('spec/fixtures/files/invalid.txt'))
    fill_in 'task_value', with: 10
    click_button 'Enviar'
    expect(page).to have_content('possui formato inválido')
    expect(Image.where(original_filename: 'invalid.txt')).to be_empty
  end
end
