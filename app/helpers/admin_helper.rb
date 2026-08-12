module AdminHelper
  def admin_status_badge(status)
    content_tag :span, status.to_s.capitalize, class: "admin-badge admin-badge-#{status}"
  end
end
