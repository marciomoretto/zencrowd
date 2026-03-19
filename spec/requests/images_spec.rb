require 'rails_helper'

RSpec.describe 'Images', type: :request do
  let!(:admin) { create(:user, :admin) }
  let!(:annotator) { create(:user, :annotator) }
  let!(:reviewer) { create(:user, :reviewer) }

  before do
    Review.delete_all
    AnnotationPoint.delete_all
    Annotation.delete_all
    Assignment.delete_all
    ImagemTile.delete_all
    Imagem.delete_all
    Image.delete_all
  end

  # Helper para fazer login
  def login_as(user)
    post '/login', params: { email: user.email, password: 'password123' }
    # Copia o cookie de sessão para as próximas requisições
    session_cookie_key = response.cookies.key?('_zencrowd_session') ? '_zencrowd_session' : 'session'
    if response.cookies[session_cookie_key]
      cookies[session_cookie_key] = response.cookies[session_cookie_key]
    end
    # Debug opcional
    puts "\n=== DEBUG DE LOGIN ==="
    puts "Tentando logar com: #{user.email}"
    puts "Status devolvido: #{response.status}"
    puts "Corpo devolvido: #{response.body}"
    puts "Cookies: #{response.cookies.inspect}"
    puts "======================\n"
  end

  # Helper para criar arquivo de imagem temporário
  def create_test_image(filename: 'test.jpg', content_type: 'image/jpeg', size: 1.kilobyte)
    file = Tempfile.new([filename, File.extname(filename)])
    file.write('fake image content' * (size / 20))
    file.rewind
    
    Rack::Test::UploadedFile.new(file.path, content_type, true)
  end

  describe 'GET /images' do
    context 'when logged in as admin' do
      before do
        login_as(admin)
      end

      it 'returns list of images' do
        image1 = create(:image, uploader: admin, original_filename: 'image1.jpg', task_value: 5.0)
        image2 = create(:image, uploader: admin, original_filename: 'image2.png', task_value: 10.0)

        get '/images', headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        ids = json.map { |item| item['id'] }
        expect(ids).to include(image1.id, image2.id)
        
        # Verificar que retorna na ordem correta (mais recente primeiro)
        expect(ids.index(image2.id)).to be < ids.index(image1.id)
      end

      it 'returns image details' do
        image = create(:image, uploader: admin, original_filename: 'test.jpg', task_value: 7.5, status: :available)

        get '/images', headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        
        expect(json.first['id']).to eq(image.id)
        expect(json.first['original_filename']).to eq('test.jpg')
        expect(json.first['status']).to eq('available')
        expect(json.first['task_value']).to eq(7.5)
        expect(json.first['uploader']['id']).to eq(admin.id)
        expect(json.first['uploader']['name']).to eq(admin.name)
      end

      it 'includes reserver information when present' do
        image = create(:image, uploader: admin, reserver: annotator, status: :reserved, reserved_at: Time.current)

        get '/images', headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        
        expect(json.first['reserver']).not_to be_nil
        expect(json.first['reserver']['id']).to eq(annotator.id)
        expect(json.first['reserved_at']).not_to be_nil
      end

      it 'returns empty array when no images' do
        get '/images', headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json).to eq([])
      end
    end

    context 'when logged in as annotator' do
      before do
        login_as(annotator)
      end

      it 'returns forbidden' do
        get '/images', headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:forbidden)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Permissão negada')
      end
    end

    context 'when logged in as reviewer' do
      before do
        login_as(reviewer)
      end

      it 'returns forbidden' do
        get '/images', headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:forbidden)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Permissão negada')
      end
    end

    context 'when not logged in' do
      it 'returns unauthorized' do
        get '/images', headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Autenticação necessária')
      end
    end
  end

  describe 'GET /images/:id' do
    let!(:image) { create(:image, uploader: admin, original_filename: 'detalhe.jpg', task_value: 8.5, status: :available) }

    context 'when logged in as admin' do
      before do
        login_as(admin)
      end

      it 'returns image details' do
        get "/images/#{image.id}", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json['id']).to eq(image.id)
        expect(json['original_filename']).to eq('detalhe.jpg')
        expect(json['status']).to eq('available')
        expect(json['task_value']).to eq(8.5)
      end

      it 'returns not found for unknown image' do
        get '/images/999999', headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Tile not found')
      end
    end

    context 'when logged in as annotator' do
      before do
        login_as(annotator)
      end

      it 'returns forbidden' do
        get "/images/#{image.id}", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:forbidden)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Permissão negada')
      end
    end

    context 'when not logged in' do
      it 'returns unauthorized' do
        get "/images/#{image.id}", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Autenticação necessária')
      end
    end
  end

  describe 'PATCH /images/:id' do
    let!(:image) do
      create(
        :image,
        uploader: admin,
        original_filename: 'editavel.jpg',
        task_value: 8.5,
        status: :reserved,
        reserver: annotator,
        reserved_at: Time.current
      )
    end

    context 'when logged in as admin' do
      before do
        login_as(admin)
      end

      it 'updates only task value' do
        patch "/images/#{image.id}",
              params: { image: { task_value: 22.75 } },
              headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:ok)

        image.reload
        expect(image.task_value.to_f).to eq(22.75)
        expect(image.status).to eq('reserved')
      end

      it 'ignores status changes sent in params' do
        patch "/images/#{image.id}",
              params: { image: { task_value: 22.75, status: 'available' } },
              headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:ok)

        image.reload
        expect(image.task_value.to_f).to eq(22.75)
        expect(image.status).to eq('reserved')
        expect(image.reserver).to eq(annotator)
        expect(image.reserved_at).to be_present
      end
    end

    context 'when logged in as annotator' do
      before do
        login_as(annotator)
      end

      it 'returns forbidden' do
        patch "/images/#{image.id}",
              params: { image: { task_value: 11.0, status: 'available' } },
              headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:forbidden)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Permissão negada')
      end
    end

    context 'when not logged in' do
      it 'returns unauthorized' do
        patch "/images/#{image.id}",
              params: { image: { task_value: 11.0, status: 'available' } },
              headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Autenticação necessária')
      end
    end
  end

  describe 'DELETE /images/:id' do
    let!(:image) do
      create(
        :image,
        uploader: admin,
        original_filename: 'removivel.jpg',
        status: :available,
        task_value: 8.5
      )
    end

    context 'when logged in as admin' do
      before do
        login_as(admin)
      end

      it 'removes the image' do
        expect do
          delete "/images/#{image.id}", headers: { 'ACCEPT' => 'application/json' }
        end.to change(Image, :count).by(-1)

        expect(response).to have_http_status(:no_content)
      end

      it 'does not remove image with annotations' do
        create(:annotation, image: image, user: annotator)

        expect do
          delete "/images/#{image.id}", headers: { 'ACCEPT' => 'application/json' }
        end.not_to change(Image, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['errors']).to be_an(Array)
        expect(json['errors']).not_to be_empty
      end
    end

    context 'when logged in as annotator' do
      before do
        login_as(annotator)
      end

      it 'returns forbidden' do
        delete "/images/#{image.id}", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:forbidden)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Permissão negada')
      end
    end

    context 'when not logged in' do
      it 'returns unauthorized' do
        delete "/images/#{image.id}", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Autenticação necessária')
      end
    end
  end

  describe 'POST /images' do
    context 'when logged in as admin' do
      before do
        login_as(admin)
      end

      it 'uploads image successfully' do
        file = create_test_image

        post '/images', params: { file: file, task_value: 12.5 }, headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        
        expect(json['original_filename']).to include('test.jpg')
        expect(json['status']).to eq('available')
        expect(json['task_value']).to eq(12.5)
        expect(json['uploader']['id']).to eq(admin.id)
        expect(json['storage_path']).to be_present
        
        # Verificar que o arquivo foi salvo
        expect(File.exist?(Rails.root.join(json['storage_path']))).to be true
        
        # Limpar arquivo criado
        File.delete(Rails.root.join(json['storage_path']))
      end

      it 'creates image record in database' do
        file = create_test_image

        expect {
          post '/images', params: { file: file, task_value: 15.0 }, headers: { 'ACCEPT' => 'application/json' }
        }.to change { Image.count }.by(1)

        image = Image.last
        expect(image.uploader).to eq(admin)
        expect(image.status).to eq('available')
        expect(image.task_value).to eq(15.0)
        
        # Limpar arquivo criado
        File.delete(Rails.root.join(image.storage_path)) if File.exist?(Rails.root.join(image.storage_path))
      end

      it 'accepts different image formats' do
        ['image/jpeg', 'image/jpg', 'image/png'].each do |content_type|
          file = create_test_image(content_type: content_type)
          
          post '/images', params: { file: file, task_value: 10.0 }, headers: { 'ACCEPT' => 'application/json' }
          
          expect(response).to have_http_status(:created)
          
          # Limpar arquivo criado
          json = JSON.parse(response.body)
          File.delete(Rails.root.join(json['storage_path'])) if File.exist?(Rails.root.join(json['storage_path']))
        end
      end

      it 'returns error when no file is provided' do
        post '/images', params: { task_value: 10.0 }, headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Nenhum arquivo foi enviado')
      end

      it 'returns error for unsupported file type' do
        file = create_test_image(filename: 'test.pdf', content_type: 'application/pdf')

        post '/images', params: { file: file, task_value: 10.0 }, headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Formato de arquivo não suportado. Use JPG, JPEG ou PNG')
      end

      it 'allows upload without task_value' do
        file = create_test_image

        post '/images', params: { file: file }, headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json['task_value']).to be_nil
        
        # Limpar arquivo criado
        File.delete(Rails.root.join(json['storage_path'])) if File.exist?(Rails.root.join(json['storage_path']))
      end
    end

    context 'when logged in as annotator' do
      before do
        login_as(annotator)
      end

      it 'returns forbidden' do
        file = create_test_image

        post '/images', params: { file: file, task_value: 10.0 }, headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:forbidden)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Permissão negada')
      end
    end

    context 'when logged in as reviewer' do
      before do
        login_as(reviewer)
      end

      it 'returns forbidden' do
        file = create_test_image

        post '/images', params: { file: file, task_value: 10.0 }, headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:forbidden)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Permissão negada')
      end
    end

    context 'when not logged in' do
      it 'returns unauthorized' do
        file = create_test_image

        post '/images', params: { file: file, task_value: 10.0 }, headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Autenticação necessária')
      end
    end
  end
  describe 'POST /images/:id/submit' do
    let(:image) { create(:image, status: :reserved, reserver: annotator, uploader: admin) }

    # Helper para criar os arquivos fakes de submissão
    def create_upload_file(filename, content_type)
      file = Tempfile.new([filename.split('.').first, File.extname(filename)])
      file.write("fake data for #{filename}")
      file.rewind
      Rack::Test::UploadedFile.new(file.path, content_type, true)
    end

    let(:projeto_tar) { create_upload_file('projeto.tar', 'application/x-tar') }
    let(:dados_csv) { create_upload_file('dados.csv', 'text/csv') }

    context 'quando logado como o aluno (annotator) que reservou a imagem' do
      before do
        login_as(annotator)
      end

      it 'submete a anotação com sucesso e anexa os arquivos' do
        post "/images/#{image.id}/submit", params: { 
          projeto_tar: projeto_tar, 
          dados_csv: dados_csv 
        }, headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:ok)
        
        # Verifica se o status da imagem mudou na máquina de estados
        image.reload
        expect(image.status).to eq('submitted')

        # Verifica se a anotação foi criada e os arquivos foram salvos no banco
        expect(image.annotations.count).to eq(1)
        annotation = image.annotations.last
        
        expect(annotation.user).to eq(annotator)
        expect(annotation.projeto_tar).to be_attached
        expect(annotation.dados_csv).to be_attached
      end

      it 'retorna erro se faltar o arquivo .csv' do
        post "/images/#{image.id}/submit", params: { 
          projeto_tar: projeto_tar 
        }, headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Arquivos projeto_tar e dados_csv são obrigatórios')
      end

      it 'retorna erro se faltar o arquivo .tar' do
        post "/images/#{image.id}/submit", params: { 
          dados_csv: dados_csv 
        }, headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'quando logado como um aluno diferente (que não reservou a foto)' do
      let(:outro_aluno) { create(:user, :annotator) }
      
      before do
        login_as(outro_aluno)
      end

      it 'bloqueia a submissão e retorna erro de segurança' do
        post "/images/#{image.id}/submit", params: { 
          projeto_tar: projeto_tar, 
          dados_csv: dados_csv 
        }, headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Only the reserver can submit')
      end
    end
  end
  # ==========================================
  # INÍCIO DOS TESTES DA ISSUE #8 (REVISÃO)
  # ==========================================
  describe 'Sistema de Revisão (Issue #8)' do
    # Criamos uma imagem já no status 'in_review'
    let(:image_in_review) { create(:image, status: :in_review, reserver: annotator, uploader: admin) }
    
    # Criamos a anotação amarrada a essa imagem (o trabalho que o aluno enviou)
    let!(:annotation) { create(:annotation, image: image_in_review, user: annotator) }

    describe 'POST /images/:id/approve' do
      context 'quando logado como revisor' do
        before do
          login_as(reviewer)
          post "/images/#{image_in_review.id}/approve", headers: { 'ACCEPT' => 'application/json' }
        end

        it 'retorna status 200 OK' do
          expect(response).to have_http_status(:ok)
        end

        it 'muda o status da imagem para approved' do
          expect(image_in_review.reload.status).to eq('approved')
        end

        it 'cria um registro de review com status approved' do
          review = Review.last
          expect(review).not_to be_nil
          expect(review.annotation_id).to eq(annotation.id)
          expect(review.reviewer_id).to eq(reviewer.id)
          expect(review.status).to eq('approved')
        end
      end

      context 'quando um aluno tenta aprovar a própria imagem' do
        before do
          login_as(annotator)
          post "/images/#{image_in_review.id}/approve", headers: { 'ACCEPT' => 'application/json' }
        end

        it 'bloqueia a ação e retorna forbidden' do
          expect(response).to have_http_status(:forbidden)
        end
      end
    end

    describe 'POST /images/:id/reject' do
      context 'quando logado como revisor' do

        before do
          login_as(reviewer)
          post "/images/#{image_in_review.id}/reject", headers: { 'ACCEPT' => 'application/json' }
        end

        it 'retorna status 200 OK' do
          expect(response).to have_http_status(:ok)
        end

        it 'devolve a imagem para a fila (available, sem dono e sem tempo)' do
          image_in_review.reload
          expect(image_in_review.status).to eq('reserved')
          expect(image_in_review.reserver_id).to eq(annotator.id)
          expect(image_in_review.reserved_at).to be_present
        end

        it 'cria um registro de review com status rejected' do
          review = Review.last
          expect(review).not_to be_nil
          expect(review.annotation_id).to eq(annotation.id)
          expect(review.reviewer_id).to eq(reviewer.id)
          expect(review.status).to eq('rejected')
        end
      end
    end
  end
  # ==========================================
  # FIM DOS TESTES DA ISSUE #8
  # ==========================================
end
