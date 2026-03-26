require 'rails_helper'

RSpec.describe 'Imagens corte com progresso', type: :request do
  let!(:admin) { create(:user, :admin) }
  let!(:imagem) { create(:imagem) }

  def login_as(user)
    post '/login', params: { email: user.email, password: 'password123' }

    session_cookie_key = response.cookies.key?('_zencrowd_session') ? '_zencrowd_session' : 'session'
    if response.cookies[session_cookie_key]
      cookies[session_cookie_key] = response.cookies[session_cookie_key]
    end
  end

  before do
    login_as(admin)
  end

  describe 'POST /imagens/:id/cortar (json)' do
    it 'inicia o corte assincrono e retorna dados de progresso' do
      allow(CutImagemTilesJob).to receive(:perform_later)

      post cortar_imagem_path(imagem, format: :json), params: { rows: 2, cols: 2 }

      expect(response).to have_http_status(:accepted)
      body = JSON.parse(response.body)

      expect(body['progress_key']).to be_present
      expect(body['feedback_key']).to be_present
      expect(body['total_count']).to eq(4)
      expect(body['status_url']).to include("/imagens/#{imagem.id}/progresso_corte")
      expect(body['show_url']).to include("/imagens/#{imagem.id}")
      expect(body['show_url']).to include('cut_feedback_key=')
      expect(CutImagemTilesJob).to have_received(:perform_later).with(
        imagem.id,
        admin.id,
        2,
        2,
        false,
        kind_of(String),
        kind_of(String)
      )
    end

    it 'retorna erro para grade invalida' do
      post cortar_imagem_path(imagem, format: :json), params: { rows: 0, cols: 9 }

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body['error']).to eq('Linhas e colunas devem estar entre 1 e 4.')
    end
  end

  describe 'POST /imagens/:id/cortar (html)' do
    it 'exibe flash final com resumo da contagem de cabecas' do
      result = ImagemTileCutter::Result.new(
        success?: true,
        created_count: 4,
        counted_count: 3,
        warning_count: 1,
        error_count: 0,
        message_counts: { 'Imagem muito grande, tente quebrar em pedaços menores.' => 1 }
      )

      allow_any_instance_of(ImagensController).to receive(:cut_image_synchronously).and_return(result)

      post cortar_imagem_path(imagem), params: { rows: 2, cols: 2 }

      expect(response).to redirect_to(imagem_path(imagem))

      follow_redirect!
      expect(response.body).to include('Corte concluído. 4 tile(s) gerado(s). Contagem de cabeças em 3 de 4 tile(s). 1 tile(s) sem contagem.')
    end
  end

  describe 'GET /imagens/:id/progresso_corte' do
    it 'retorna o progresso salvo' do
      progress_key = SecureRandom.uuid
      payload = {
        status: 'running',
        processed_count: 3,
        total_count: 8,
        created_count: 3,
        message: 'Processando tile 3 de 8...'
      }

      ImagemCutProgressStore.write(imagem_id: imagem.id, progress_key: progress_key, payload: payload)

      get progresso_corte_imagem_path(imagem, key: progress_key), headers: { 'ACCEPT' => 'application/json' }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['status']).to eq('running')
      expect(body['processed_count']).to eq(3)
      expect(body['total_count']).to eq(8)
      expect(body['message']).to eq('Processando tile 3 de 8...')
    end

    it 'retorna not found quando nao ha progresso para a chave informada' do
      get progresso_corte_imagem_path(imagem, key: 'inexistente'), headers: { 'ACCEPT' => 'application/json' }

      expect(response).to have_http_status(:not_found)
      body = JSON.parse(response.body)
      expect(body['status']).to eq('not_found')
      expect(body['error']).to eq('Progresso de corte não encontrado.')
    end
  end

  describe 'GET /imagens/:id com cut_feedback_key' do
    it 'consome feedback pendente e exibe flash na tela' do
      feedback_key = SecureRandom.uuid

      ImagemCutProgressStore.write_feedback(
        imagem_id: imagem.id,
        feedback_key: feedback_key,
        payload: {
          flash_level: 'notice',
          message: 'Corte concluído. 4 tile(s) gerado(s). Contagem de cabeças em 4 de 4 tile(s).'
        }
      )

      get imagem_path(imagem, cut_feedback_key: feedback_key)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Corte concluído. 4 tile(s) gerado(s). Contagem de cabeças em 4 de 4 tile(s).')
      expect(ImagemCutProgressStore.read_feedback(imagem_id: imagem.id, feedback_key: feedback_key)).to be_nil
    end
  end
end
