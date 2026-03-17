class HomeController < ApplicationController
  skip_before_action :verify_authenticity_token

  def index
    respond_to do |format|
      format.html # Renderiza app/views/home/index.html.erb
      format.json do
        render json: {
          application: 'ZenCrowd API',
          version: '0.1.0',
          status: 'running',
          endpoints: {
            authentication: {
              login: { method: 'POST', path: '/login' },
              logout: { method: 'DELETE', path: '/logout' },
              me: { method: 'GET', path: '/me' }
            },
            images: {
              list: { method: 'GET', path: '/images', auth: 'admin' },
              upload: { method: 'POST', path: '/images', auth: 'admin' }
            }
          },
          documentation: '/docs'
        }
      end
    end
  end
end
