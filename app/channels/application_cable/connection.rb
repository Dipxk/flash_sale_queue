module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user_token

    def connect
      self.current_user_token = request.params[:user_token].presence ||
                                request.headers["X-User-Token"].presence
      reject_unauthorized_connection unless current_user_token
    end
  end
end
