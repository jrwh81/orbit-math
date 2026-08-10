class ChangePuzzlesDifficultyDefault < ActiveRecord::Migration[7.1]
  def change
    change_column_default :puzzles, :difficulty, from: "normal", to: "beginner"
  end
end
