class CreateUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :users do |t|
      t.string :username, null: false
      t.string :email
      t.string :password_digest, null: false
      t.string :display_name

      t.timestamps
    end

    add_index :users, :username, unique: true
    add_index :users, :email, unique: true, where: "email IS NOT NULL"
  end
end
