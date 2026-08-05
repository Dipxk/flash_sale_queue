class ApplicationController < ActionController::Base
  # API clients (curl/Postman) don't send authenticity tokens.
  protect_from_forgery with: :null_session
end
