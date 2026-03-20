require 'rails_helper'

RSpec.describe 'Admin gerencia eventos', type: :feature do
  def login_as(user)
    visit login_path
    fill_in 'E-mail', with: user.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'
  end

  scenario 'admin cria evento e envia imagem vinculada automaticamente' do
    admin = create(:user, :admin)

    login_as(admin)

    visit new_admin_evento_path

    fill_in 'Nome', with: 'Evento de Teste'
    select 'Direita', from: 'Categoria'
    attach_file 'Imagem', Rails.root.join('spec/fixtures/files/sample.jpg')
    click_button 'Salvar'

    evento = Evento.order(:id).last
    imagem = evento.imagens.order(:id).last

    expect(page).to have_content('Evento criado com sucesso.')
    expect(page).to have_content('Evento de Teste')
    expect(evento.nome).to eq('Evento de Teste')
    expect(evento.categoria).to eq('direita')
    expect(evento.imagens.count).to eq(1)
    expect(imagem.arquivo.filename.to_s).to eq('sample.jpg')
    expect(imagem.evento).to eq(evento)
  end

  scenario 'admin edita evento e envia nova imagem vinculada' do
    admin = create(:user, :admin)
    evento = create(:evento, nome: 'Evento Antigo', categoria: :esquerda)
    imagem1 = create(:imagem, evento: evento)

    login_as(admin)

    visit edit_admin_evento_path(evento)

    fill_in 'Nome', with: 'Evento Atualizado'
    select 'Outro', from: 'Categoria'
    attach_file 'Imagem', Rails.root.join('spec/fixtures/files/sample2.jpg')
    click_button 'Salvar'

    expect(page).to have_content('Evento atualizado com sucesso.')

    evento.reload
    expect(evento.nome).to eq('Evento Atualizado')
    expect(evento.categoria).to eq('outro')
    expect(imagem1.reload.evento).to eq(evento)
    expect(evento.imagens.count).to eq(2)
    expect(evento.imagens.order(:id).last.arquivo.filename.to_s).to eq('sample2.jpg')
  end

  scenario 'admin remove evento e desassocia imagens' do
    admin = create(:user, :admin)
    evento = create(:evento, nome: 'Evento para Remocao')
    imagem = create(:imagem, evento: evento)

    login_as(admin)

    visit admin_eventos_path

    click_link 'Evento para Remocao'
    click_button 'Remover'

    expect(page).to have_content('Evento Evento para Remocao removido com sucesso.')
    expect(Evento.exists?(evento.id)).to be(false)
    expect(imagem.reload.evento).to be_nil
  end

  scenario 'annotator nao acessa CRUD de eventos' do
    annotator = create(:user, :annotator)

    login_as(annotator)

    visit admin_eventos_path

    expect(page).to have_content('Permissão negada')
    expect(page).to have_current_path(dashboard_path)
  end
end
