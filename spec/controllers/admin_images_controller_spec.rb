require 'rails_helper'

RSpec.describe Admin::ImagesController, type: :controller do
  include ActiveJob::TestHelper

  let(:admin) { create(:user, :admin) }
  let(:annotator) { create(:user, :annotator) }
  let(:valid_file) do
    fixture_file_upload(Rails.root.join('spec/fixtures/files/sample.jpg'), 'image/jpeg')
  end
  let(:invalid_file) do
    fixture_file_upload(Rails.root.join('spec/fixtures/files/invalid.txt'), 'text/plain')
  end

  describe 'GET #new' do
    it 'permite acesso para admin' do
      session[:user_id] = admin.id
      get :new
      expect(response).to have_http_status(:ok)
    end

    it 'nega acesso para não-admin' do
      session[:user_id] = annotator.id
      get :new
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to match(/Acesso restrito/)
    end
  end

  describe 'POST #create' do
    before { session[:user_id] = admin.id }

    it 'cria imagem válida' do
      ActiveJob::Base.queue_adapter = :test
      clear_enqueued_jobs

      expect {
        post :create, params: { images: [valid_file] }
      }.to change(Image, :count).by(1)
       .and have_enqueued_job(CountTileHeadsJob)

      image = Image.last
      expect(image.task_value.to_f).to eq(0.0)
      expect(image.head_count).to be_nil
      expect(image.status).to eq('available')
      expect(image.original_filename).to eq('sample.jpg')
      expect(response).to redirect_to(admin_tiles_path)
      expect(flash[:notice]).to be_present
    end

    it 'não cria imagem com arquivo inválido' do
      expect {
        post :create, params: { images: [invalid_file] }
      }.not_to change(Image, :count)
      expect(flash[:alert]).to match(/formato inválido/)
    end

    it 'não permite acesso para não-admin' do
      session[:user_id] = annotator.id
      post :create, params: { images: [valid_file] }
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to match(/Acesso restrito/)
    end
  end
end
