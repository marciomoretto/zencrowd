class HomeController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :redirect_authenticated_user_to_dashboard!, only: [:index]
  layout 'public'

  def index
    approved_or_better = Tile.where(status: %i[approved payment_requested paid])
    @approved_or_better_tiles_count = approved_or_better.count
    @approved_or_better_heads_count = approved_or_better.where.not(head_count: nil).sum(:head_count)

    respond_to do |format|
      format.html # Renderiza app/views/home/index.html.erb
      format.json do
        render json: {
          application: 'ZenCrowd API',
          version: '0.1.0',
          status: 'running',
          endpoints: {
            tiles: {
              list: { method: 'GET', path: '/tiles', auth: 'admin' },
              upload: { method: 'POST', path: '/tiles', auth: 'admin' }
            }
          },
          documentation: '/docs'
        }
      end
    end
  end
end
