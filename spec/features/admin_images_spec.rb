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
    expect(page).to have_content('Imagens cadastradas')
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
    expect(current_path).to eq(root_path)
  end
end
