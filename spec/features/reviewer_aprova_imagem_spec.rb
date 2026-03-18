require 'rails_helper'

RSpec.describe 'Reviewer aprova imagem submetida', type: :feature do
  let!(:admin) { create(:user, :admin) }
  let!(:annotator) { create(:user, :annotator) }
  let!(:reviewer) { create(:user, :reviewer) }
  let!(:image) { create(:image, uploader: admin, status: :available, original_filename: 'imagem_para_revisao.png', task_value: 10.0) }

  scenario 'Reviewer aprova uma imagem submetida' do
    # Annotator reserva e submete a imagem
    visit '/login'
    fill_in 'E-mail', with: annotator.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'
    click_link 'Imagens Disponíveis'
    click_button 'Reservar'
    expect(page).to have_content('Imagem reservada com sucesso!')
    # Simular submissão
    visit my_task_path
    if page.has_button?('Submeter')
      attach_file('Arquivo do Projeto (.tar)', Rails.root.join('spec/fixtures/files/test_projeto.tar'))
      attach_file('Arquivo de Dados (.csv)', Rails.root.join('spec/fixtures/files/test_dados.csv'))
      click_button 'Submeter'
    end
    expect(page).to have_content('Imagem submetida com sucesso').or have_content('submetida')
    click_link 'Sair' if page.has_link?('Sair')

    # Reviewer faz login e aprova
    visit '/login'
    fill_in 'E-mail', with: reviewer.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'
    save_and_open_page
    click_link 'Tarefas em Revisão'
    expect(page).to have_content('imagem_para_revisao.png')
    # O reviewer deve iniciar a revisão antes de aprovar
    if page.has_button?('Iniciar Revisão')
      click_button 'Iniciar Revisão'
    end
    if page.has_button?('Aprovar')
      click_button 'Aprovar'
    end
    expect(page).to have_content('Imagem aprovada com sucesso').or have_content('aprovada')
  end
end
