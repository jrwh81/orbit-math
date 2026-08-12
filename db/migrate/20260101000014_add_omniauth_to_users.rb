class AddOmniauthToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :provider, :string
    add_column :users, :uid, :string
    add_index :users, [:provider, :uid], unique: true

    # OAuth-only accounts (signed up via Google/Facebook) never set a
    # password -- has_secure_password's own validation is disabled for
    # them (see User model) and a User-level validation takes over,
    # required only for traditional signups. The database itself must
    # allow a null digest for that to be possible at all.
    change_column_null :users, :password_digest, true
  end
end
