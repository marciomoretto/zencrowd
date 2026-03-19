module ApplicationHelper
	def human_tile_status(status)
		status_key = status.to_s
		fallback_labels = {
			'available' => 'Disponível',
			'reserved' => 'Reservada',
			'submitted' => 'Submetida',
			'in_review' => 'Em revisão',
			'approved' => 'Aprovada',
			'rejected' => 'Rejeitada',
			'paid' => 'Paga'
		}

		I18n.t("activerecord.attributes.image.statuses.#{status_key}", default: fallback_labels[status_key] || status_key.humanize)
	end

	def human_image_status(status)
		human_tile_status(status)
	end

	def human_review_status(status)
		status_key = status.to_s
		fallback_labels = {
			'approved' => 'Aprovada',
			'rejected' => 'Rejeitada'
		}

		I18n.t("activerecord.attributes.review.statuses.#{status_key}", default: fallback_labels[status_key] || status_key.humanize)
	end

	# Retorna os links de navegação por papel do usuário autenticado.
	def navigation_links_for(user)
		return [] unless user

		case
		when user.admin?
			[
				{ path: dashboard_path, icon: 'bi-speedometer2', label: 'Dashboard' },
				{ path: tiles_path, icon: 'bi-grid-3x3-gap', label: 'Tiles' },
				{ path: new_tile_path, icon: 'bi-upload', label: 'Upload de Imagem' },
				{ path: admin_users_path, icon: 'bi-people', label: 'Usuários' }
			]
		when user.annotator?
			[
				{ path: dashboard_path, icon: 'bi-speedometer2', label: 'Dashboard' },
				{ path: available_tiles_path, icon: 'bi-grid-3x3-gap', label: 'Tiles Disponíveis' },
				{ path: my_task_path, icon: 'bi-pencil-square', label: 'Minha Tarefa' }
			]
		when user.reviewer?
			[
				{ path: dashboard_path, icon: 'bi-speedometer2', label: 'Dashboard' },
				{ path: reviewer_reviews_path, icon: 'bi-check-circle', label: 'Tarefas em Revisão' }
			]
		else
			[]
		end
	end
end
