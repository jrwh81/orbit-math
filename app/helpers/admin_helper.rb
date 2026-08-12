module AdminHelper
  def admin_status_badge(status)
    content_tag :span, status.to_s.capitalize, class: "admin-badge admin-badge-#{status}"
  end

  def oauth_provider_badge(user)
    label, css_class =
      case user.provider
      when "google_oauth2" then ["Google", "admin-badge-google"]
      when "facebook" then ["Facebook", "admin-badge-facebook"]
      else ["Password", "admin-badge-password"]
      end

    content_tag :span, label, class: "admin-badge #{css_class}"
  end
end
