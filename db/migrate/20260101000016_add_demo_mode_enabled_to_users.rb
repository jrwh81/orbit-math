class AddDemoModeEnabledToUsers < ActiveRecord::Migration[7.1]
  def change
    # Solo-only guided walkthrough (see DemoController/demo_controller.js).
    # Defaults true -- "enabled until turned off" is the whole point of the
    # feature, so every existing and future account starts with it on.
    add_column :users, :demo_mode_enabled, :boolean, null: false, default: true
  end
end
