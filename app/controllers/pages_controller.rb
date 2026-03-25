class PagesController < ApplicationController
  def sobre
  end

  def contato
  end

  def enviar_contato
    nome = params[:nome]
    email = params[:email]
    mensagem = params[:mensagem]

    # Dispara o e-mail
    ContatoMailer.nova_mensagem(nome, email, mensagem).deliver_now

    # Redireciona de volta para a tela de contato com uma mensagem de sucesso
    flash[:success] = "Sua mensagem foi enviada com sucesso! Nossa equipe responderá em breve."
    redirect_to contato_path
  end

  def ajuda
  end

  def faq
  end

  def documentacao
  end
end
