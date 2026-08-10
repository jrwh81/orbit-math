class Move < ApplicationRecord
  belongs_to :game_session
  belongs_to :user

  validates :path, presence: true
  validates :ops, presence: true

  def expression
    return "" if path.blank?

    str = path.first["value"].to_s
    ops.each_with_index do |op, i|
      str += " #{op == "*" ? "\u00D7" : "+"} #{path[i + 1]["value"]}"
    end
    str
  end
end
