class PostcommitController < ApplicationController

  def index
    require 'jira4r'
  end

  def create
    @payload = ActiveSupport::JSON.decode params[:payload]
  end

end
