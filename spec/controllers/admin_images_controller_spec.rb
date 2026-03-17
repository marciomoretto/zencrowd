require 'rails_helper'

RSpec.describe Admin::ImagesController, type: :controller do
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
      sign_in admin
      get :new
      expect(response).to have_http_status(:ok)
    end

    it 'nega acesso para não-admin' do
      sign_in annotator
      get :new
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to match(/Acesso restrito/)
    end
  end

  describe 'POST #create' do
    before { sign_in admin }

    it 'cria imagem válida' do
      expect {
        post :create, params: { images: [valid_file], task_value: 12.5 }
      }.to change(Image, :count).by(1)
      image = Image.last
      expect(image.task_value.to_f).to eq(12.5)
      expect(image.status).to eq('available')
      expect(image.original_filename).to eq('sample.jpg')
      expect(response).to redirect_to(admin_images_path)
      expect(flash[:notice]).to be_present
    end

    it 'não cria imagem com arquivo inválido' do
      expect {
        post :create, params: { images: [invalid_file], task_value: 10 }
      }.not_to change(Image, :count)
      expect(flash[:alert]).to match(/formato inválido/)
    end

    it 'não permite acesso para não-admin' do
      sign_out admin
      sign_in annotator
      post :create, params: { images: [valid_file], task_value: 10 }
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to match(/Acesso restrito/)
    end
  end
end
