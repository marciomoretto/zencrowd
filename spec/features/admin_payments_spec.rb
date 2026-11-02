require 'rails_helper'

RSpec.describe 'Admin acessa pagamentos', type: :feature do
  let!(:admin) { create(:user, :admin) }
  let!(:finance) { create(:user, :finance) }
  let!(:annotator) { create(:user, :annotator) }

  prepend_before do
    Review.delete_all
    AnnotationPoint.delete_all
    Annotation.delete_all
    Assignment.delete_all
    Tile.delete_all
  end

  scenario 'admin pode acessar pagamentos sem exibir link no menu' do
    requested_tile = create(:tile, status: :payment_requested, reserver: annotator, original_filename: 'tile_solicitado.jpg', task_value: 11.0)
    paid_tile = create(:tile, status: :paid, reserver: annotator, original_filename: 'tile_pago.jpg', task_value: 13.5)

    create(:annotation, image: requested_tile, user: annotator)
    create(:annotation, image: paid_tile, user: annotator)

    visit login_path
    fill_in 'E-mail', with: admin.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'

    expect(page).to have_current_path(dashboard_path)
    expect(page).not_to have_link('Pagamentos')

    visit admin_payments_path
    expect(page).to have_current_path(admin_payments_path)
    expect(page).to have_content('A receber')
    expect(page).to have_content('Solicitado')
    expect(page).to have_content('Pago')
    expect(page).to have_content(annotator.name)
    expect(page).to have_content('R$11,00')
    expect(page).to have_content('R$13,50')
    expect(page).to have_button('Pagar')
  end

  scenario 'admin paga valor solicitado de um annotator' do
    requested_tile_1 = create(:tile, status: :payment_requested, reserver: annotator, original_filename: 'tile_solicitado_1.jpg', task_value: 10.0)
    requested_tile_2 = create(:tile, status: :payment_requested, reserver: annotator, original_filename: 'tile_solicitado_2.jpg', task_value: 5.0)

    create(:annotation, image: requested_tile_1, user: annotator)
    create(:annotation, image: requested_tile_2, user: annotator)

    visit login_path
    fill_in 'E-mail', with: admin.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'

    visit admin_payments_path

    within('tr', text: annotator.name) do
      click_button 'Pagar'
    end

    expect(page).to have_current_path(admin_payments_path)
    expect(page).to have_content('Pagamento processado para')
    expect(requested_tile_1.reload.status).to eq('paid')
    expect(requested_tile_2.reload.status).to eq('paid')

    payment = Payment.last
    expect(payment.amount).to eq(15.to_d)
    visit admin_user_path(annotator)
    expect(page).to have_link("Pagamento ##{payment.id}")
    expect(page).to have_content('R$15,00')

    click_link "Pagamento ##{payment.id}"
    expect(page).to have_content('Tiles incluídos neste pagamento')
    expect(page).to have_content('tile_solicitado_1.jpg')
    expect(page).to have_content('tile_solicitado_2.jpg')
    expect(page).to have_content('R$10,00')
    expect(page).to have_content('R$5,00')
  end

  scenario 'annotator não acessa aba de pagamentos admin' do
    visit login_path
    fill_in 'E-mail', with: annotator.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'

    visit admin_payments_path

    expect(page).to have_current_path(dashboard_path)
    expect(page).to have_content('Permissão negada')
  end

  scenario 'financeiro visualiza card e acessa aba de pagamentos' do
    requested_tile = create(:tile, status: :payment_requested, reserver: annotator, original_filename: 'tile_financeiro.jpg', task_value: 15.0)
    create(:annotation, image: requested_tile, user: annotator)

    visit login_path
    fill_in 'E-mail', with: finance.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'

    expect(page).to have_current_path(dashboard_path)
    expect(page).to have_content('Pagamentos')

    click_link 'Pagamentos', match: :first

    expect(page).to have_current_path(admin_payments_path)
    expect(page).to have_content(annotator.name)
    expect(page).to have_button('Pagar')
  end
end
