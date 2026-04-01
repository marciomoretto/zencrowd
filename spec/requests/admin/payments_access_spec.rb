require 'rails_helper'

RSpec.describe 'Admin::Payments access', type: :request do
  let!(:finance_user) do
    create(
      :user,
      :finance,
      usp_login: '9000001',
      onboarding_completed: true,
      cpf: '12345678901',
      pix_key_type: 'random',
      pix_key: 'finance-key'
    )
  end
  let!(:annotator) do
    create(
      :user,
      :annotator,
      usp_login: '9000002',
      onboarding_completed: true,
      cpf: '12345678902',
      pix_key_type: 'random',
      pix_key: 'annotator-key'
    )
  end

  def login_as(user)
    client = instance_double(SenhaUnicaUSP::Client)
    allow(SenhaUnicaUSP::Client).to receive(:new).and_return(client)
    allow(client).to receive(:fetch_payload!).and_return(
      'loginUsuario' => user.usp_login,
      'nomeUsuario' => user.name,
      'emailPrincipalUsuario' => user.email
    )

    get '/auth/usp/callback', params: { oauth_verifier: 'verifier-token' }
  end

  it 'permite acesso de usuário financeiro à página de pagamentos' do
    login_as(finance_user)

    get admin_payments_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Pagamentos')
  end

  it 'nega acesso de annotator à página de pagamentos' do
    login_as(annotator)

    get admin_payments_path

    expect(response).to have_http_status(:redirect)
    expect(response).to redirect_to(root_path)
  end
end
