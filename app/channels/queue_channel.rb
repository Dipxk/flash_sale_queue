class QueueChannel < ApplicationCable::Channel
  def subscribed
    entry = QueueEntry.find_by(user_token: current_user_token)
    reject && return unless entry

    stream_for entry
    transmit self.class.payload_for(entry)
  end

  def unsubscribed
    stop_all_streams
  end

  def self.broadcast_to_user(entry)
    broadcast_to(entry, payload_for(entry))
  end

  def self.payload_for(entry)
    {
      type: "queue_update",
      user_token: entry.user_token,
      status: entry.status,
      people_ahead: entry.people_ahead,
      position: entry.position,
      expires_at: entry.expires_at,
      admitted: entry.status == "active",
      checked_out: entry.status == "checked_out"
    }
  end
end
