require 'rails_helper'

RSpec.describe "Pages", type: :request do
  describe "GET /sobre" do
    it "returns http success" do
      get "/pages/sobre"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /contato" do
    it "returns http success" do
      get "/pages/contato"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /ajuda" do
    it "returns http success" do
      get "/pages/ajuda"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /faq" do
    it "returns http success" do
      get "/pages/faq"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /documentacao" do
    it "returns http success" do
      get "/pages/documentacao"
      expect(response).to have_http_status(:success)
    end
  end

end
