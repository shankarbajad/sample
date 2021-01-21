class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :null_session, if: Proc.new { |c| c.request.format == 'application/json' }

  before_action :set_locale, :set_company_and_company_control
  after_action :set_csrf_cookie_for_ng

  def set_locale
    I18n.locale = params[:locale] || I18n.default_locale
    Rails.application.routes.default_url_options[:locale]= I18n.locale
  end

  def after_sign_in_path_for(resource)
    company = Companydatum.find(current_user.useraccount.companydatum_id)
    if company.setupdone
      # if Subscription::CheckProduct.timesheet_clock_status(company.company_control)
      #   configure_path
      # else
      #   if current_user.has_role?("admin")
      #     admin_mains_path
      #   else
      #     mains_path 
      #   end  
      # end
      if current_user.has_role?("admin")
        admin_mains_path
      else
        mains_path 
      end   
    else
      new_admin_question_path
    end
  end

  def set_csrf_cookie_for_ng
    cookies['XSRF-TOKEN'] = form_authenticity_token if protect_against_forgery?
  end

  def page_not_found
    respond_to do |format|
      format.html { render template: 'errors/not_found_error', layout: 'layouts/blank', status: 404 }
      format.all  { render nothing: true, status: 404 }
    end
  end

  def is_timeoff_free_trial?
    (@company_control.product_code.length == 1 && (@company_control.product_code.include? "F")) || Subscription::CheckProduct.timeoffproduct_status(@company_control)
  end

  def is_timesheets_free_trial?
    (@company_control.product_code.length == 1 && (@company_control.product_code.include? "F")) || Subscription::CheckProduct.timesheets_product_status(@company_control)
  end

  protected

    def set_company_and_company_control
      if current_user
        @company = Companydatum.find(current_user.useraccount.companydatum_id)
        @company_control = @company.company_control
      end
    end

    def verified_request?
      super || valid_authenticity_token?(session, request.headers['X-XSRF-TOKEN'])
    end
end
