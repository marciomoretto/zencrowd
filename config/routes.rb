Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Root path - API info
  root "home#index"

  # Authentication routes
  post '/login', to: 'sessions#create'
  delete '/logout', to: 'sessions#destroy'
  get '/me', to: 'sessions#show'

  # Images routes (admin only)
  resources :images, only: [:index, :create] do
    member do
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
