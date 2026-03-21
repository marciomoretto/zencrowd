require 'rails_helper'

RSpec.describe 'Admin::Settings', type: :request do
  let(:admin) { create(:user, :admin, password: 'password123') }
  let(:annotator) { create(:user, :annotator, password: 'password123') }

  describe 'PATCH /admin/settings' do
    context 'when user is admin' do
      before do
        post '/login', params: { email: admin.email, password: 'password123' }
      end

      it 'updates settings and redirects' do
        patch '/admin/settings', params: {
          settings: {
            task_value_per_head_cents: 40,
            task_expiration_hours: 24
          }
        }

        expect(response).to redirect_to('/admin/settings')
        follow_redirect!
        expect(response.body).to include('Configurações atualizadas com sucesso.')
        expect(AppSetting.task_value_per_head_cents).to eq(40)
        expect(AppSetting.task_expiration_hours).to eq(24)
      end
    end

    context 'when user is not admin' do
      before do
        post '/login', params: { email: annotator.email, password: 'password123' }
      end

      it 'denies access' do
        patch '/admin/settings', params: {
          settings: {
            task_value_per_head_cents: 40,
            task_expiration_hours: 24
          }
        }

        expect(response).to redirect_to('/')
      end
    end
  end
end
