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

  describe 'registro de pagamento pelo financeiro' do
    let!(:requested_tiles) do
      create_list(:tile, 2, status: :payment_requested, reserver: annotator, task_value: 12.5)
    end

    it 'marca como pagas as tarefas solicitadas do marcador' do
      login_as(finance_user)

      post pay_requested_admin_payment_path(annotator)

      expect(response).to redirect_to(admin_payments_path)
      expect(flash[:alert]).to be_blank
      expect(flash[:notice]).to include('2 tarefa(s)')
      expect(requested_tiles.map { |tile| tile.reload.status }).to all(eq('paid'))
    end

    it 'não paga nada quando não há valor solicitado' do
      requested_tiles.each { |tile| tile.update!(status: :approved) }
      login_as(finance_user)

      post pay_requested_admin_payment_path(annotator)

      expect(response).to redirect_to(admin_payments_path)
      expect(flash[:alert]).to be_present
    end

    it 'nega o pagamento ao marcador' do
      login_as(annotator)

      post pay_requested_admin_payment_path(annotator)

      expect(response).to redirect_to(root_path)
      expect(requested_tiles.map { |tile| tile.reload.status }).to all(eq('payment_requested'))
    end
  end

  it 'nega acesso de annotator à página de pagamentos' do
    login_as(annotator)

    get admin_payments_path

    expect(response).to have_http_status(:redirect)
    expect(response).to redirect_to(root_path)
  end

  it 'permite ao financeiro consultar os dados de pagamento do marcador' do
    login_as(finance_user)

    get admin_user_path(annotator)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(annotator.cpf, annotator.pix_key, 'Voltar para pagamentos')
    expect(response.body).not_to include('Voltar para usuários')
  end

  it 'não exibe links para contas de outros perfis ao financeiro' do
    login_as(finance_user)

    get admin_payments_path

    expect(response.body).to include("href=\"#{admin_user_path(annotator)}\"")
    expect(response.body).not_to include("href=\"#{admin_user_path(finance_user)}\"")
  end

  %i[admin finance reviewer uploader visitor].each do |role|
    it "nega ao financeiro a consulta de contas do perfil #{role}" do
      target = create(:user, role)
      login_as(finance_user)

      get admin_user_path(target)

      expect(response).to redirect_to(admin_payments_path)
      expect(response.body).not_to include('Dados do Usuário')
    end
  end

  it 'nega a consulta dos dados de outros marcadores ao marcador' do
    login_as(annotator)

    get admin_user_path(create(:user, :annotator))

    expect(response).to redirect_to(root_path)
  end

  it 'mantém o acesso do administrador aos dados de todos os perfis' do
    admin = create(:user, :admin, usp_login: '9000003', onboarding_completed: true,
                   cpf: '12345678903', pix_key_type: 'random', pix_key: 'admin-key')
    login_as(admin)

    get admin_user_path(finance_user)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(finance_user.pix_key, 'Voltar para usuários')
  end

  it 'nega ao financeiro o gerenciamento de usuários' do
    login_as(finance_user)

    get admin_users_path
    expect(response).to redirect_to(root_path)

    patch toggle_block_admin_user_path(annotator)
    expect(response).to redirect_to(root_path)
    expect(annotator.reload).not_to be_blocked

    patch update_role_admin_user_path(annotator), params: { role: 'admin' }
    expect(response).to redirect_to(root_path)
    expect(annotator.reload).to be_annotator
  end
end
