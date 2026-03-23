require 'rails_helper'

RSpec.describe 'Admin::Images', type: :feature do
  let!(:admin) { create(:user, :admin) }
  let!(:annotator) { create(:user, :annotator) }
  let!(:image1) { create(:image, original_filename: 'img1.jpg', status: :available, task_value: 10.0) }
  let!(:image2) { create(:image, original_filename: 'img2.png', status: :reserved, task_value: 20.0) }
  let!(:image3) { create(:image, original_filename: 'img3.png', status: :paid, task_value: 30.0) }

  prepend_before do
    Review.delete_all
    AnnotationPoint.delete_all
    Annotation.delete_all
    Assignment.delete_all
    Image.delete_all

    AppSetting.update_operational_settings!(
      task_value_per_head_cents: 0,
      task_expiration_hours: 48,
      budget_limit_reais: 1000,
      min_payment_reais: 0
    )
  end

  def login_as(user)
    visit login_path
    fill_in 'E-mail', with: user.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'
  end

  scenario 'admin acessa listagem de imagens' do
    paid_total = Image.where(status: :paid).sum(:task_value).to_d
    to_pay_total = Image.where(status: %i[reserved submitted in_review approved]).sum(:task_value).to_d
    remaining_total = [1000.to_d - (paid_total + to_pay_total), 0].max

    login_as(admin)
    visit admin_images_path
    expect(page).to have_content('Tiles cadastrados')
    expect(page).to have_content('Total pago')
    expect(page).to have_content(ActionController::Base.helpers.number_to_currency(paid_total, unit: 'R$', separator: ',', delimiter: '.', format: '%u%n'))
    expect(page).to have_content('Total a pagar')
    expect(page).to have_content(ActionController::Base.helpers.number_to_currency(to_pay_total, unit: 'R$', separator: ',', delimiter: '.', format: '%u%n'))
    expect(page).to have_content('Orçamento')
    expect(page).to have_content('R$1.000,00')
    expect(page).to have_content('Execução do orçamento')
    expect(page).to have_content('Comprometido:')
    expect(page).to have_content('Restante')
    expect(page).to have_content(ActionController::Base.helpers.number_to_currency(remaining_total, unit: 'R$', separator: ',', delimiter: '.', format: '%u%n'))
    expect(page).to have_selector('table')
    expect(page).to have_content(image1.original_filename)
    expect(page).to have_content(image2.original_filename)
    expect(page).to have_content(image3.original_filename)
    expect(page).to have_content(image1.status)
    expect(page).to have_content(image2.status)
    expect(page).to have_content(image3.status)
    expect(page).to have_content(image1.task_value)
    expect(page).to have_content(image2.task_value)
    expect(page).to have_content(image3.task_value)
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
    expect(page).to have_content('valor da tarefa é calculado automaticamente')
  end

  scenario 'annotator não acessa tela de upload' do
    login_as(annotator)
    visit new_admin_image_path
    expect(page).to have_content('Acesso restrito ao administrador')
    expect(current_path).to eq(dashboard_path)
  end

  scenario 'admin faz upload de uma imagem válida' do
    allow(TileHeadCounter).to receive(:call) do |tile:, expose_error:|
      tile.update_columns(head_count: 12, task_value: 5.0)
      { status: :ok, count: 12 }
    end

    login_as(admin)
    visit new_admin_image_path
    attach_file('images[]', Rails.root.join('spec/fixtures/files/sample.jpg'))
    click_button 'Enviar'
    expect(page).to have_content('1 tile(s) enviado(s) com sucesso')
    expect(Image.last.task_value.to_f).to eq(5.0)
    expect(Image.last.head_count).to eq(12)
    expect(Image.last.status).to eq('available')
    expect(Image.last.original_filename).to eq('sample.jpg')
  end

  scenario 'admin faz upload de múltiplas imagens' do
    allow(TileHeadCounter).to receive(:call) do |tile:, expose_error:|
      tile.update_columns(head_count: 100, task_value: 15.0)
      { status: :ok, count: 100 }
    end

    login_as(admin)
    visit new_admin_image_path
    attach_file('images[]', [Rails.root.join('spec/fixtures/files/sample.jpg'), Rails.root.join('spec/fixtures/files/sample2.jpg')])
    click_button 'Enviar'
    expect(page).to have_content('2 tile(s) enviado(s) com sucesso')
    expect(Image.order(:created_at).last(2).pluck(:task_value)).to all(eq(15.0))
    expect(Image.order(:created_at).last(2).pluck(:head_count)).to all(eq(100))
    expect(Image.order(:created_at).last(2).pluck(:status)).to all(eq('available'))
  end

  scenario 'admin tenta enviar arquivo inválido' do
    login_as(admin)
    visit new_admin_image_path
    attach_file('images[]', Rails.root.join('spec/fixtures/files/invalid.txt'))
    click_button 'Enviar'
    expect(page).to have_content('possui formato inválido')
    expect(Image.where(original_filename: 'invalid.txt')).to be_empty
  end
end
