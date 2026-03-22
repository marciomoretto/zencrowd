require 'rails_helper'

RSpec.describe 'Image Transitions API', type: :request do
  let!(:admin) { create(:user, :admin) }
  let!(:annotator) { create(:user, :annotator) }
  let!(:reviewer) { create(:user, :reviewer) }
  let!(:image) { create(:image, uploader: admin, status: :available) }

  def login_as(user)
    # Limpa sessão anterior para permitir alternar de usuário no mesmo exemplo.
    delete '/logout'

    post '/login', params: { email: user.email, password: 'password123' }
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

  describe 'POST /images/:id/reserve' do
    context 'when logged in as annotator' do
      before { login_as(annotator) }

      it 'reserves an available image' do
        post "/images/#{image.id}/reserve", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['status']).to eq('reserved')
        expect(json['reserver']['id']).to eq(annotator.id)
        expect(json['reserved_at']).to be_present
      end

      it 'returns error when image is not available' do
        image.update!(status: :reserved)
        post "/images/#{image.id}/reserve", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Tile is not available')
      end

      it 'returns error when user already has a reserved image' do
        other_image = create(:image, uploader: admin, status: :available)
        image.reserve!(annotator)

        post "/images/#{other_image.id}/reserve", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('User already has a reserved tile')
      end

      it 'returns error when project budget is exhausted for new reservation' do
        AppSetting.update_operational_settings!(
          task_value_per_head_cents: AppSetting.task_value_per_head_cents,
          task_expiration_hours: AppSetting.task_expiration_hours,
          budget_limit_reais: 100
        )

        create(:image, uploader: admin, status: :paid, task_value: 70)
        create(:image, uploader: admin, status: :submitted, task_value: 20)
        image.update!(task_value: 15)

        post "/images/#{image.id}/reserve", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Project is out of budget for new reservations')
      end

      it 'releases expired reservation from the same user before reserving another image' do
        AppSetting.update_operational_settings!(
          task_value_per_head_cents: AppSetting.task_value_per_head_cents,
          task_expiration_hours: 2
        )

        expired_image = create(
          :image,
          uploader: admin,
          status: :reserved,
          reserver: annotator,
          reserved_at: 3.hours.ago,
          reservation_expires_at: 30.minutes.ago
        )

        post "/images/#{image.id}/reserve", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['status']).to eq('reserved')
        expect(json['reserver']['id']).to eq(annotator.id)

        expect(expired_image.reload.status).to eq('abandoned')
        expect(expired_image.reserver).to be_nil
        expect(expired_image.reserved_at).to be_nil
        expect(expired_image.reservation_expires_at).to be_nil
      end
    end

    context 'when logged in as reviewer' do
      before { login_as(reviewer) }

      it 'returns forbidden' do
        post "/images/#{image.id}/reserve", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when not logged in' do
      it 'returns unauthorized' do
        post "/images/#{image.id}/reserve", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /images/:id/submit' do
    before do
      image.update!(status: :reserved, reserver: annotator, reserved_at: Time.current)
    end

    context 'when logged in as the reserver' do
      before { login_as(annotator) }

      def create_upload_file(filename, content_type)
        file = Tempfile.new([filename.split('.').first, File.extname(filename)])
        file.write("fake data for #{filename}")
        file.rewind
        Rack::Test::UploadedFile.new(file.path, content_type, true)
      end

      let(:projeto_tar) { create_upload_file('projeto.tar', 'application/x-tar') }
      let(:dados_csv) { create_upload_file('dados.csv', 'text/csv') }

      it 'submits the annotation' do
        post "/images/#{image.id}/submit", params: {
          projeto_tar: projeto_tar,
          dados_csv: dados_csv
        }, headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['status']).to eq('in_review')
      end

      it 'returns error when image is not reserved' do
        image.update!(status: :available)
        post "/images/#{image.id}/submit", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Tile is not reserved')
      end
    end

    context 'when logged in as different annotator' do
      let(:other_annotator) { create(:user, :annotator) }
      before { login_as(other_annotator) }

      it 'returns error' do
        post "/images/#{image.id}/submit", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Only the reserver can submit')
      end
    end

    context 'when not logged in' do
      it 'returns unauthorized' do
        post "/images/#{image.id}/submit", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /images/:id/give_up' do
    before do
      image.update!(status: :reserved, reserver: annotator, reserved_at: Time.current)
    end

    context 'when logged in as the reserver annotator' do
      before { login_as(annotator) }

      it 'releases the reservation and makes image available' do
        post "/images/#{image.id}/give_up", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['status']).to eq('abandoned')
        expect(json['reserver']).to be_nil
        expect(json['reserved_at']).to be_nil
      end
    end

    context 'when logged in as another annotator' do
      let(:other_annotator) { create(:user, :annotator) }

      before { login_as(other_annotator) }

      it 'returns error' do
        post "/images/#{image.id}/give_up", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Only the reserver can give up this tile')
      end
    end

    context 'when logged in as reviewer' do
      before { login_as(reviewer) }

      it 'returns forbidden' do
        post "/images/#{image.id}/give_up", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when not logged in' do
      it 'returns unauthorized' do
        post "/images/#{image.id}/give_up", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /images/:id/start_review' do
    before do
      image.update!(status: :submitted)
    end

    context 'when logged in as reviewer' do
      before { login_as(reviewer) }

      it 'starts review' do
        post "/images/#{image.id}/start_review", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['status']).to eq('in_review')
      end

      it 'returns error when image is not submitted' do
        image.update!(status: :available)
        post "/images/#{image.id}/start_review", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Tile is not submitted')
      end
    end

    context 'when logged in as annotator' do
      before { login_as(annotator) }

      it 'returns forbidden' do
        post "/images/#{image.id}/start_review", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when not logged in' do
      it 'returns unauthorized' do
        post "/images/#{image.id}/start_review", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /images/:id/approve' do
    before do
      image.update!(status: :in_review)
    end

    context 'when logged in as reviewer' do
      before { login_as(reviewer) }

      it 'approves the annotation' do
        create(:annotation, image: image, user: annotator)
        post "/images/#{image.id}/approve", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['status']).to eq('approved')
      end

      it 'returns error when image is not in review' do
        image.update!(status: :available)
        post "/images/#{image.id}/approve", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Tile is not in review')
      end
    end

    context 'when logged in as annotator' do
      before { login_as(annotator) }

      it 'returns forbidden' do
        post "/images/#{image.id}/approve", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when not logged in' do
      it 'returns unauthorized' do
        post "/images/#{image.id}/approve", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /images/:id/reject' do
    before do
      image.update!(status: :in_review, reserver: annotator, reserved_at: 1.hour.ago)
    end

    context 'when logged in as reviewer' do
      before { login_as(reviewer) }

      it 'rejects the annotation' do
        create(:annotation, image: image, user: annotator)
        post "/images/#{image.id}/reject", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['status']).to eq('rejected')
        expect(json['reserver']['id']).to eq(annotator.id)
      end

      it 'returns error when image is not in review' do
        image.update!(status: :available)
        post "/images/#{image.id}/reject", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Tile is not in review')
      end
    end

    context 'when logged in as annotator' do
      before { login_as(annotator) }

      it 'returns forbidden' do
        post "/images/#{image.id}/reject", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when not logged in' do
      it 'returns unauthorized' do
        post "/images/#{image.id}/reject", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /images/:id/mark_paid' do
    before do
      image.update!(status: :approved)
    end

    context 'when logged in as admin' do
      before { login_as(admin) }

      it 'marks image as paid' do
        post "/images/#{image.id}/mark_paid", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['status']).to eq('paid')
      end

      it 'returns error when image is not approved' do
        image.update!(status: :in_review)
        post "/images/#{image.id}/mark_paid", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Tile is not approved')
      end
    end

    context 'when logged in as annotator' do
      before { login_as(annotator) }

      it 'returns forbidden' do
        post "/images/#{image.id}/mark_paid", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when not logged in' do
      it 'returns unauthorized' do
        post "/images/#{image.id}/mark_paid", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /images/:id/expire_reservation' do
    before do
      image.update!(status: :reserved, reserver: annotator, reserved_at: Time.current)
    end

    context 'when logged in as admin' do
      before { login_as(admin) }

      it 'expires the reservation' do
        post "/images/#{image.id}/expire_reservation", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['status']).to eq('abandoned')
        expect(json['reserver']).to be_nil
        expect(json['reserved_at']).to be_nil
      end

      it 'returns error when image is not reserved' do
        image.update!(status: :available)
        post "/images/#{image.id}/expire_reservation", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Tile is not reserved')
      end
    end

    context 'when logged in as annotator' do
      before { login_as(annotator) }

      it 'returns forbidden' do
        post "/images/#{image.id}/expire_reservation", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when not logged in' do
      it 'returns unauthorized' do
        post "/images/#{image.id}/expire_reservation", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'complete workflow' do
    it 'follows the happy path from available to paid' do
      # Reserve
      login_as(annotator)
      post "/images/#{image.id}/reserve", headers: { 'ACCEPT' => 'application/json' }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['status']).to eq('reserved')

      # Submit (enviando arquivos obrigatórios)
      def create_upload_file(filename, content_type)
        file = Tempfile.new([filename.split('.').first, File.extname(filename)])
        file.write("fake data for #{filename}")
        file.rewind
        Rack::Test::UploadedFile.new(file.path, content_type, true)
      end
      projeto_tar = create_upload_file('projeto.tar', 'application/x-tar')
      dados_csv = create_upload_file('dados.csv', 'text/csv')
      post "/images/#{image.id}/submit", params: {
        projeto_tar: projeto_tar,
        dados_csv: dados_csv
      }, headers: { 'ACCEPT' => 'application/json' }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['status']).to eq('in_review')

      # Approve
      login_as(reviewer)
      post "/images/#{image.id}/approve", headers: { 'ACCEPT' => 'application/json' }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['status']).to eq('approved')

      # Mark paid
      login_as(admin)
      post "/images/#{image.id}/mark_paid", headers: { 'ACCEPT' => 'application/json' }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['status']).to eq('paid')
    end
  end
end
