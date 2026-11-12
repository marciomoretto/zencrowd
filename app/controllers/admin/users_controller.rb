class Admin::UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!, except: [:index, :show]
  before_action -> { authorize_role!(:admin, :finance) }, only: [:index, :show]
  before_action :set_user, only: [:show, :toggle_block, :update_role]
  before_action :prevent_self_management!, only: [:toggle_block, :update_role]

  def index
    users = current_user.finance? ? User.annotator : User.all
    @users = paginate_scope(users.order(created_at: :desc))
  end

  def show
    unless current_user.admin? || @user.annotator?
      if request.format.json?
        render json: { error: 'Permissão negada' }, status: :forbidden
      else
        redirect_to admin_payments_path, alert: 'Permissão negada'
      end
      return
    end

    @tasks = paginate_scope(tasks_for_user) if current_user.finance?
  end

  def toggle_block
    @user.update!(blocked: !@user.blocked?)

    if @user.blocked?
      flash[:notice] = "Usuário #{@user.name} foi bloqueado."
    else
      flash[:notice] = "Usuário #{@user.name} foi desbloqueado."
    end

    redirect_to admin_users_path
  end

  def update_role
    new_role = params[:role].to_s

    unless User.roles.key?(new_role)
      flash[:alert] = 'Papel inválido.'
      return redirect_to admin_users_path
    end

    if @user.update(role: new_role)
      flash[:notice] = "Papel de #{@user.name} atualizado para #{new_role}."
    else
      flash[:alert] = @user.errors.full_messages.to_sentence
    end

    redirect_to admin_users_path
  end

  private

  def tasks_for_user
    annotation_tile_ids = Annotation.where(user_id: @user.id).select(:image_id)
    paid_tile_ids = PaymentItem.joins(:payment).where(payments: { annotator_id: @user.id }).select(:tile_id)
    associated = Tile.where(reserver_id: @user.id)
                     .or(Tile.where(id: annotation_tile_ids))
                     .or(Tile.where(id: paid_tile_ids))
    returned = Tile.where(status: :reserved, reserver_id: @user.id).where(
      'EXISTS (SELECT 1 FROM annotations a INNER JOIN reviews r ON r.annotation_id = a.id ' \
      'WHERE a.image_id = images.id AND a.user_id = ? AND r.status = ? ' \
      'AND a.id = (SELECT latest.id FROM annotations latest WHERE latest.image_id = images.id ' \
      'ORDER BY latest.created_at DESC, latest.id DESC LIMIT 1))',
      @user.id, Review.statuses[:rejected]
    )
    associated.where(status: %i[submitted in_review approved rejected payment_requested paid])
              .or(returned)
              .includes(payment_item: :payment)
              .order(updated_at: :desc, id: :desc)
  end

  def set_user
    @user = User.find(params[:id])
  end

  def prevent_self_management!
    return unless @user == current_user

    flash[:alert] = 'Você não pode alterar seu próprio usuário nesta tela.'
    redirect_to admin_users_path
  end
end
