Rails.application.routes.draw do
  if ENV["SIDEKIQ_WEB_USER"].present? && ENV["SIDEKIQ_WEB_PASSWORD"].present?
    require "sidekiq/web"

    Sidekiq::Web.use Rack::Auth::Basic do |username, password|
      ActiveSupport::SecurityUtils.secure_compare(username, ENV.fetch("SIDEKIQ_WEB_USER")) &
        ActiveSupport::SecurityUtils.secure_compare(password, ENV.fetch("SIDEKIQ_WEB_PASSWORD"))
    end

    mount Sidekiq::Web => "/admin/sidekiq"
  end

  get 'sobre', to: 'pages#sobre'
  get 'contato', to: 'pages#contato'
  post 'contato', to: 'pages#enviar_contato'
  get 'ajuda', to: 'pages#ajuda'
  get 'faq', to: 'pages#faq'
  get 'documentacao', to: 'pages#documentacao'
  get 'eventos/:id', to: 'uploader/eventos#public_show', as: :evento_publico
  get 'eventos/:id/pasta', to: 'uploader/eventos#public_pasta', as: :evento_publico_pasta
  
  namespace :admin do
    resources :tiles, controller: 'images', only: [:index, :new, :create]
    resources :images, only: [:index, :new, :create]
    resources :payments, only: [:index] do
      member do
        post :pay_requested
      end
    end
    resource :settings, only: [:show, :update], controller: 'settings'
    resources :users, only: [:index] do
      member do
        patch :toggle_block
        patch :update_role
      end
    end
  end
  # Datasets (admin)
  resources :datasets, only: [:index, :create, :destroy] do
    member do
      get :download
    end
  end

  # Annotator tasks
  get '/available_tiles', to: 'annotator_tasks#available', as: :available_tiles
  get '/available_images', to: 'annotator_tasks#available', as: :available_images
  get '/my_task', to: 'annotator_tasks#my_task', as: :my_task
  get '/completed_tasks', to: 'annotator_tasks#completed', as: :completed_tasks

  begin
    require "zen_plot"
  rescue LoadError
    begin
      require "web_plot_digitizer"
    rescue LoadError
      # Digitizer gem not available in this runtime.
    end
  end

  digitizer_engine = if defined?(ZenPlot::Engine)
                       ZenPlot::Engine
                     elsif defined?(WebPlotDigitizer::Engine)
                       WebPlotDigitizer::Engine
                     end

  mount digitizer_engine => "/digitizer" if digitizer_engine

  namespace :reviewer do
    resources :reviews, only: [:index, :show]
  end

  namespace :uploader do
    resources :eventos do
      resource :relatorio, only: [:show, :new, :create, :edit, :update, :destroy], controller: 'relatorios'

      member do
        get :pasta
        get :mosaic
        post :render_mosaic
        post :cut_mosaic
        get :mosaic_cut_progress
        get :finalize_mosaic_cut
        get :mosaic_progress
      end
    end

    resource :drone_settings, only: [:show, :create]
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Root path - API info
  root "home#index"
  get '/dashboard', to: 'dashboard#index', as: :dashboard
  post '/dashboard/request_payment', to: 'dashboard#request_payment', as: :request_payment_dashboard

  # Authentication via USP OAuth
  get '/login', to: 'sessions#new', as: :login
  post '/login', to: 'sessions#create' if Rails.env.test?
  get '/auth/usp/callback', to: 'sessions#callback', as: :usp_callback
  get '/callback', to: 'sessions#callback'
  delete '/logout', to: 'sessions#destroy', as: :logout

  # First-login onboarding
  resource :onboarding, only: [:show, :update], controller: 'onboarding'
  get '/meus-dados', to: 'meus_dados#show', as: :meus_dados
  get '/meus-dados/editar', to: 'meus_dados#edit', as: :edit_meus_dados
  patch '/meus-dados', to: 'meus_dados#update'

  # Imagens metadata flow (admin)
  get '/imagens', to: 'imagens#index', as: :imagens
  get '/imagens/new', to: 'imagens#new', as: :new_imagem
  post '/imagens', to: 'imagens#create'
  get '/imagens/:id', to: 'imagens#show', as: :imagem
  patch '/imagens/:id', to: 'imagens#update'
  post '/imagens/:id/cortar', to: 'imagens#cortar', as: :cortar_imagem
  get '/imagens/:id/progresso_corte', to: 'imagens#progresso_corte', as: :progresso_corte_imagem
  delete '/imagens/:id', to: 'imagens#destroy'

  # Tiles routes (admin only, preferred naming)
  resources :tiles, controller: 'images', only: [:index, :create, :new, :show, :update, :destroy] do
    collection do
      get :export_bundle
    end

    member do
      get :preview            # Render image file inline for details page
      get :download_image     # Download original tile image file
      get :export_points_csv  # Download annotation points as CSV
      get :zen_plot_points    # Load persisted ZenPlot points for this tile
      post :zen_plot_points   # Persist ZenPlot points for this tile
      post :finalize_zen_plot_points # Persist points and mark them as finalized
      post :count_heads       # Admin triggers manual head counting from show
      post :reserve           # Annotator reserves image
      post :give_up           # Annotator gives up reserved image
      post :submit            # Annotator submits annotation
      post :start_review      # Reviewer starts review
      post :approve           # Reviewer approves
      post :reject            # Reviewer rejects
      post :mark_paid         # Admin marks as paid
      post :expire_reservation # Admin expires reservation
    end
  end

  # Legacy image routes kept for backward compatibility
  resources :images, only: [:index, :create, :new, :show, :update, :destroy] do
    member do
      get :preview            # Render image file inline for details page
      get :download_image     # Download original tile image file
      get :export_points_csv  # Download annotation points as CSV
      post :count_heads       # Admin triggers manual head counting from show
      post :reserve           # Annotator reserves image
      post :give_up           # Annotator gives up reserved image
      post :submit            # Annotator submits annotation
      post :start_review      # Reviewer starts review
      post :approve           # Reviewer approves
      post :reject            # Reviewer rejects
      post :mark_paid         # Admin marks as paid
      post :expire_reservation # Admin expires reservation
    end
  end

  # Defines the root path route ("/")
  # root "posts#index"
end
