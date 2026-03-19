# frozen_string_literal: true

# Authorization concern for role-based access control
#
# Defines permissions for each user role:
#
# Admin:
#   - Create users
#   - Upload tiles
#   - View all tiles and tasks
#   - Access dataset export
#
# Annotator:
#   - View available tiles for annotation
#   - Reserve one tile at a time
#   - View reserved tile
#   - Create annotations (mark points)
#   - Submit annotation
#
# Reviewer:
#   - View submitted annotations
#   - Review annotations
#   - Approve or reject annotations
#
# Usage in controllers:
#   before_action :authorize_admin!, only: [:create, :upload]
#   before_action :authorize_annotator!, only: [:reserve, :annotate]
#   before_action :authorize_reviewer!, only: [:review]

module Authorization
  extend ActiveSupport::Concern

  included do
    # Make authorization methods available in views
    helper_method :can_upload_images?, :can_annotate?, :can_review?
  end

  # Permission check methods
  def can_upload_images?
    authenticated? && current_user.admin?
  end

  def can_annotate?
    authenticated? && current_user.annotator?
  end

  def can_review?
    authenticated? && current_user.reviewer?
  end

  def can_export_dataset?
    authenticated? && current_user.admin?
  end

  def can_create_users?
    authenticated? && current_user.admin?
  end

  # Authorization enforcement methods
  # These render error responses if user lacks permission
  def require_upload_permission!
    unless can_upload_images?
      render json: { error: 'Apenas administradores podem fazer upload de imagens' }, 
             status: :forbidden
    end
  end

  def require_annotation_permission!
    unless can_annotate?
      render json: { error: 'Apenas anotadores podem criar anotações' }, 
             status: :forbidden
    end
  end

  def require_review_permission!
    unless can_review?
      render json: { error: 'Apenas revisores podem revisar anotações' }, 
             status: :forbidden
    end
  end

  def require_export_permission!
    unless can_export_dataset?
      render json: { error: 'Apenas administradores podem exportar o dataset' }, 
             status: :forbidden
    end
  end
end
