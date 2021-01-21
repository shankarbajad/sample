class OrganizationsController < ApplicationController
	before_action :authenticate_user!
  before_action :check_org_chart_subscription, only:[:index], unless: :is_timeoff_free_trial?
  before_action :check_organization_subscription, only: [:new], unless: :is_timeoff_free_trial?

  include Subscription
  respond_to :json

  def index
    @data = {}
    @data[:cols] = [{:label => "Name", :pattern => "", :type => "string"}, {:label => "Manager", :pattern => "", :type => "string"}, {:label => "ToolTip", :pattern => "", :type => "string"}]
    @data[:rows] = @company.useraccounts.collect{|emp| {c: [{v: emp.id, f: emp.status == 'I' ? emp.fullname+"<div style='color:red; font-style:italic'>Inactive</div>" : emp.fullname},{v: emp.try(:manager_id)},{v: ''}]}}
    respond_to do |format|
      format.json { render json: @data }
      format.html 
    end
  end

  def new;end

  # Method to get list of divisions in Company
  def division
    @divisions = @company.divisions
    respond_to do |format|
      format.json { render json: @divisions}
    end
  end

  # Method to get list of departments in Company
  def department
    @departments = @company.departments
    respond_to do |format|
      format.json { render json: @departments}
    end
  end

  # Method to get list of jobfamilies in Company
  def jobfamily
    @jobfamilies = @company.jobfamilies
    respond_to do |format|
      format.json { render json: @jobfamilies}
    end
  end

  # Method to get list of regions in Company
  def region
    @regions = @company.companyregions
    respond_with @regions
  end

  #--Methods to Create, update and delete the Organization Division
  def create_division
  	@division = @company.divisions.create(name: params[:division][:name])
    respond_to do |format|
      format.json { render json: @division }
    end
  end

  def update_division
    @division = Division.find(params[:id])
    @division.update_attributes(name: params[:name])
    respond_with @division
  end

  def delete_division
    @division = Division.find(params[:id])
    @division.destroy
    respond_with @division
  end
  #-- end --#

  #--Methods to Create, update and delete the Organization Department
  def create_department
    @department = @company.departments.create(name: params[:department][:name],division_id: params[:division_id])
  	respond_to do |format|
      format.json { render json: @department }
    end
  end

  def update_department
    @department = Department.find(params[:id])
    @department.update_attributes(name: params[:name],division_id: params[:division_id])
    respond_with @department
  end

  def delete_department
    @department = Department.find(params[:id])
    @department.destroy
    respond_with @department
  end
  #-- end --#

  #--Methods to Create, update and delete the Organization Jobfamily
  def create_jobfamily
    @jobfamily = @company.jobfamilies.create(name: params[:jobfamily][:name])
    respond_to do |format|
      format.json { render json: @jobfamily }
    end
  end

  def update_jobfamily
    @jobfamily = Jobfamily.find(params[:id])
    @jobfamily.update_attributes(name: params[:name])
    respond_with @jobfamily
  end

  def delete_jobfamily
    @jobfamily = Jobfamily.find(params[:id])
    @jobfamily.destroy
    respond_with @jobfamily
  end
  #-- end --#

  #--Methods to Create, update and delete the Organization Region
  def create_region
    @region = @company.companyregions.new(region_params)
    if @region.save
      render json: @region.as_json, status: :ok
    else
      render json: {region: @region.errors, status: :no_content}
    end
  end

  def update_region
    @region = Companyregion.find(params[:id])
    @region.update_attributes(regionname: params[:regionname],regioncode: params[:regioncode])
    respond_with @region
  end
  
  def delete_region
    @region = Companyregion.find(params[:id])
    @region.destroy
    respond_with @region
  end
  #-- end --#

  def country_list
    @countries = Companyregion.regions.collect{|region| {name: region[0], code: region[1]}}
    respond_with @countries
  end

  def company_detail
    respond_with @company
  end

  private

    def region_params
      params.require(:region).permit(:regionname, :regioncode)
    end

    def check_org_chart_subscription
      unless CheckProduct.orgchart_status(@company_control)
        flash[:danger] = "Premium plan option"
        redirect_to_dashboard
      end
    end

    def check_organization_subscription
      unless CheckProduct.holidays_and_events_status(@company_control)
        flash[:danger] = "Premium plan option"
        redirect_to_dashboard
      end
    end

    def redirect_to_dashboard
      current_user.has_role? (:admin) ? (redirect_to admin_mains_path) : (redirect_to mains_path)
    end
end
