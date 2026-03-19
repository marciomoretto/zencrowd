module ApplicationHelper
	def human_image_status(status)
		I18n.t("activerecord.attributes.image.statuses.#{status}", default: status.to_s.humanize)
	end

	# Retorna os links de navegação por papel do usuário autenticado.
	def navigation_links_for(user)
		return [] unless user

		case
		when user.admin?
			[
				{ path: dashboard_path, icon: 'bi-speedometer2', label: 'Dashboard' },
				{ path: images_path, icon: 'bi-images', label: 'Imagens' },
				{ path: new_image_path, icon: 'bi-upload', label: 'Upload de Imagem' },
				{ path: admin_users_path, icon: 'bi-people', label: 'Usuários' }
			]
		when user.annotator?
			[
				{ path: dashboard_path, icon: 'bi-speedometer2', label: 'Dashboard' },
				{ path: available_images_path, icon: 'bi-images', label: 'Imagens Disponíveis' },
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
