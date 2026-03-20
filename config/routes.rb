Rails.application.routes.draw do
  namespace :admin do
    resources :tiles, controller: 'images', only: [:index, :new, :create]
    resources :images, only: [:index, :new, :create]
    resources :eventos
    resources :users, only: [:index] do
      member do
        patch :toggle_block
        patch :update_role
      end
    end
  end
  # Dataset export (admin)
  get '/export_dataset', to: 'datasets#export', as: :export_dataset

  # Annotator tasks
  get '/available_tiles', to: 'annotator_tasks#available', as: :available_tiles
  get '/available_images', to: 'annotator_tasks#available', as: :available_images
  get '/my_task', to: 'annotator_tasks#my_task', as: :my_task

  namespace :reviewer do
    resources :reviews, only: [:index, :show]
  end
  # Registration routes
  get '/signup', to: 'registrations#new', as: :signup
  post '/signup', to: 'registrations#create'
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Root path - API info
  root "home#index"
  get '/dashboard', to: 'dashboard#index', as: :dashboard

  # Authentication routes
  get '/login', to: 'sessions#new', as: :login
  post '/login', to: 'sessions#create'
  delete '/logout', to: 'sessions#destroy', as: :logout
  get '/me', to: 'sessions#show'

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
    member do
      get :preview            # Render image file inline for details page
      post :count_heads       # Admin triggers manual head counting from show
      post :reserve           # Annotator reserves image
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
      post :count_heads       # Admin triggers manual head counting from show
      post :reserve           # Annotator reserves image
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
