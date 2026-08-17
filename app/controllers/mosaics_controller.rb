class MosaicsController < ApplicationController
  skip_before_action :redirect_incomplete_onboarding!
  skip_before_action :logout_if_blocked_user!
  layout false

  def show
    absolute = MosaicStorage.absolute_path(params[:path])
    return head :not_found unless absolute && File.file?(absolute)

    send_file absolute.to_s, disposition: 'inline'
  rescue StandardError
    head :not_found
  end
end
