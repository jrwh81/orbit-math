class CreatePuzzles < ActiveRecord::Migration[7.1]
  def change
    create_table :puzzles do |t|
      t.integer :size, null: false, default: 8
      t.jsonb :grid, null: false, default: []
      t.jsonb :targets, null: false, default: []
      t.string :difficulty, null: false, default: "normal"
      t.integer :seed

      t.timestamps
    end
  end
end
