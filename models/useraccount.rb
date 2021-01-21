class Useraccount < ActiveRecord::Base
  include Timeoffbankcheck
  has_many :empworkdays, dependent: :destroy
  has_many :jfworkdays, dependent: :destroy
  belongs_to :user
  belongs_to :companydatum
  belongs_to :division
  belongs_to :department
  belongs_to :jobfamily
  belongs_to :companyregion
  belongs_to :manager, :class_name => 'Useraccount',:foreign_key => :manager_id
  has_many :employees, :class_name => 'Useraccount',:foreign_key => :manager_id
  has_one :useraccountcontact, dependent: :destroy
  has_one :external_user
  has_many :timeoffrequests , dependent: :destroy
  has_many :remote_calendars, dependent: :destroy
  has_many :teamviewmembers,foreign_key: "manager_id"
  has_many :notifyboxes, foreign_key: "sender_id"
  has_many :notifyrecipients, foreign_key: "recipient_id"
  has_many :timeoffbanks, dependent: :destroy
  has_many :timeoffbankhistyears, dependent: :destroy
  has_many :timeoffbankhistmons, dependent: :destroy
  has_many :timeoffbankdailyhists, dependent: :destroy
  has_many :accrualdates, dependent: :destroy
  has_many :tsteammembers, dependent: :destroy
  has_many :read_features, dependent: :destroy
  has_many :tsperiodhours
  
  has_attached_file :profilepic,
          :path => "/profilepics/:id/:basename.:extension",
          :storage => :s3,
          :default_url => "/assets/default-user.jpg",
          :https_enabled=> true,
          :s3_protocol => :https,
          :s3_host_name => 's3-us-west-1.amazonaws.com',
          :s3_credentials => {
            s3_region: 'us-west-1',
            bucket: 'daysplan-secure-us',
            access_key_id: 'AKIAI3SEMANHELHHWL5A',
            secret_access_key: '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'
          }

  validates_attachment :profilepic,
             content_type: { content_type: ["image/jpeg", "image/gif", "image/png"] }
  after_create :create_timeoffbank, :increment_user_count,:create_timeoffbankhistyear
  after_destroy :decrement_user_count
  after_update :is_manager_change

  default_scope { order(:lastname) }

  # Method to create new records in timeoffbank table when new employee created
  def create_timeoffbank
    companydatum.timeoffcategories.each do |timeoffcategory|
      timeoffbanks.find_or_create_by(accrued: 0.0, adjustment: 0.0, carryover: 0.0, pending: 0.0, used: 0.0,timeoffcategory_id: timeoffcategory.id)
    end
  end

  # Method to create new records in timeoffbankhistyear table when new employee created
  def create_timeoffbankhistyear
    companydatum.timeoffcategories.each do |timeoffcategory|
      timeoffbankhistyears.find_or_create_by(bankyear: Date.today.year.next,accrued: 0.0, adjustment: 0.0, carryover: 0.0, pending: 0.0, used: 0.0,timeoffcategory_id: timeoffcategory.id)
    end
    companydatum.timeoffcategories.each do |timeoffcategory|
      timeoffbankhistyears.find_or_create_by(bankyear: Date.today.year.next.next,accrued: 0.0, adjustment: 0.0, carryover: 0.0, pending: 0.0, used: 0.0,timeoffcategory_id: timeoffcategory.id)
    end
  end

  def increment_user_count
    self.companydatum.update_attributes(usercount: (self.companydatum.usercount + 1))
  end

  def decrement_user_count
    self.companydatum.update_attributes(usercount: (self.companydatum.usercount - 1))
  end

  def is_manager_change
    if manager_id_changed?
      timeoffrequests.where(reqstatus: "P").each do |timeoffrequest|
        timeoffrequest.notifyrecipients.delete_all
        timeoffrequest.notifyrecipients.create(status: "U", recipient_id: manager_id)
      end
    end
  end

  #====== Start --  Implementaion of Time off data export report generation code ===========
  def self.to_timeoffdate_export_csv year, company
    log_file = Logger.new("#{Rails.root}/log/log_file.log", "w")
    log_file.level = Logger::INFO
    begin
      CSV.generate do |csv|
        csv << ["Date","Employee","Region","Type","Status","Jan","Feb","Mar","Apr","May","June","Jul","Aug","Sept","Oct","Nov","Dec","Total"]
        all.each do |useraccount|
          (1..12).each do |month|
            useraccount.timeoffrequests.where(reqstatus: ["P","A"]).order(reqstart: :asc).by_month_and_year(month,year).each do |timeoffrequest|
              (timeoffrequest.reqstart.to_date).upto(timeoffrequest.reqend.to_date){ |date|
                if company.company_control.work_week == "S"
                  hours = company.company_control.work_hours_per_day if company.company_control.work_week == "S"
                  csv << useraccount.set_timeoffdate_export_array(timeoffrequest,month,date,hours) if ( !useraccount.is_weekend?(date) && !useraccount.is_holiday?(date))
                else
                  @schedule = useraccount.get_emp_custom_schedule(date)
                  hours = (Time.parse(@schedule.endtime) - Time.parse(@schedule.starttime)).abs / 1.hours rescue 0.0
                   csv << useraccount.set_timeoffdate_export_array(timeoffrequest,month,date,hours) if (@schedule.try(:isworkday) && !useraccount.is_holiday?(date))
                end 
              }
            end
          end
        end
      end
    rescue => e
      log_file.fatal "#{e.message} #{__LINE__} #{'-' * 30}\n\n"
    end
  end

  def set_timeoffdate_export_array timeoffrequest,month,date, hours
    log_file = Logger.new("#{Rails.root}/log/log_file.log", "w")
    log_file.level = Logger::INFO
    begin
      data = Array.new(18)
      data[0] = date.strftime("%d/%m/%Y")
      data[1] = fullname
      data[2] = companyregion.regionname
      data[3] = timeoffrequest.timeoffcategory.timeoffname
      data[4] = Timeoffrequest::STATUS[timeoffrequest.reqstatus]
      month = date.month == month ? month : (date.month)
      days_diff = (timeoffrequest.reqend.to_date - timeoffrequest.reqstart.to_date).to_i.abs + 1
      data[4+month] = days_diff == 1 ? single_day_timeoffunit_conversion(days_diff,timeoffrequest,hours) :  multiple_days_timeoffunit_conversion(timeoffrequest,hours)
      data
    rescue => e
      log_file.fatal "#{e.message} #{__LINE__} #{'-' * 30}\n\n"
    end
  end
  #====== End --  Implementaion of Time off data export report generation code ===========

  def self.to_csv(fields, columns, exportdatum)
    CSV.generate do |csv|
      fields.delete("timeoffcategory_id")
      columns.delete("Time Off Name")
      csv << columns if exportdatum.header
      timeoffreport_fields = ["accrued","adjustment","used","pending","carryover","balance","dates"]
      if exportdatum.send(exportdatum.universe_type).present?
        where(exportdatum.universe_type.to_sym => exportdatum.send(exportdatum.universe_type)).each do |user|
          csv << export_timeoff_data(fields,timeoffreport_fields, exportdatum,user)
        end
      else
        exportdatum.companydatum.useraccounts.each do |user|
          csv << export_timeoff_data(fields,timeoffreport_fields, exportdatum,user)
        end
      end
    end
  end

  def self.export_timeoff_data fields,timeoffreport_fields, exportdatum,user
    if exportdatum.startdate.present? && exportdatum.enddate.present?
      fields.map{ |attr| timeoffreport_fields.include?(attr.include?("-") ? attr.split('-')[1] : attr) ? (attr.include?("dates") ? user.send("get_timeoffdates",attr,exportdatum) : user.send("get_total_accrued",attr,exportdatum)) : user.send(attr)}
    else
      table = user.set_bank_table(exportdatum)
      fields.map{ |attr| timeoffreport_fields.include?(attr.include?("-") ? attr.split('-')[1] : attr) ? (attr.include?("dates") ? user.send("get_timeoffdates",attr,exportdatum) : user.send(table,attr)) : user.send(attr)}
    end
  end

  def self.to_pdf(fields, exportdatum)
    pdf = []
    timeoffreport_fields = ["timeoffcategory_id","accrued","adjustment","used","pending","carryover","balance"]

    if exportdatum.send(exportdatum.universe_type).present?
      where(exportdatum.universe_type.to_sym => exportdatum.send(exportdatum.universe_type)).each do |user|
        if exportdatum.startdate.present? || exportdatum.enddate.present? 
        else
          data = user.set_no_of_records_and_table(exportdatum)
          (0..data[0]).each do |num|
            pdf << fields.map{ |attr| (num == 0 ? (timeoffreport_fields.include?(attr) ? user.send(data[1],attr,num) : user.send(attr)) : timeoffreport_fields.include?(attr) ? user.send(data[1],attr,num) : '') }
          end
        end
      end
    else
      exportdatum.companydatum.useraccounts.each do |user|
        data = user.set_no_of_records_and_table(exportdatum)
        (0..data[0]).each do |num|
          pdf << fields.map{ |attr| (num == 0 ? (timeoffreport_fields.include?(attr) ? user.send(data[1],attr,num) : user.send(attr)) : timeoffreport_fields.include?(attr) ? user.send(data[1],attr,num) : '') }
        end
      end
    end

    pdf
  end

  def self.to_timesheet_csv(fields, columns, tsregularitems,exportdatum)
    timesheetdate = exportdatum.timesheetdate
    CSV.generate do |csv|
      csv << columns if exportdatum.header
      if exportdatum.send(exportdatum.universe_type).present?
        where(exportdatum.universe_type.to_sym => exportdatum.send(exportdatum.universe_type)).each do |user|
          csv << tsregularitem_data(timesheetdate.tsstartdate,timesheetdate.tsenddate,timesheetdate.id,user,fields,columns,tsregularitems)
        end
      else
        exportdatum.companydatum.useraccounts.each do |user|
          csv << tsregularitem_data(timesheetdate.tsstartdate,timesheetdate.tsenddate,timesheetdate.id,user,fields,columns,tsregularitems)
        end
      end
    end
  end  

  def self.to_timesheet_pdf(fields,columns,tsregularitems,exportdatum)
    pdf = []
    timesheetdate = exportdatum.timesheetdate
    if exportdatum.send(exportdatum.universe_type).present?
      where(exportdatum.universe_type.to_sym => exportdatum.send(exportdatum.universe_type)).each do |user|
        pdf << tsregularitem_data(timesheetdate.tsstartdate,timesheetdate.tsenddate,timesheetdate.id,user,fields,columns,tsregularitems)
      end
    else
      exportdatum.companydatum.useraccounts.each do |user|
        pdf << tsregularitem_data(timesheetdate.tsstartdate,timesheetdate.tsenddate,timesheetdate.id,user,fields,columns,tsregularitems)
      end
    end
    pdf
  end

  def self.to_ts_process_csv(fields,columns,tsregularitems,timesheetperiod,companydatum)
    CSV.generate do |csv|
      csv << columns
      companydatum.useraccounts.each do |user|
        csv << tsregularitem_data(timesheetperiod.tsstartdate,timesheetperiod.tsenddate,timesheetperiod.id,user,fields,columns,tsregularitems)
      end
    end
  end

  def self.tsregularitem_data tsstartdate,tsenddate,timesheetdate_id,user,fields,columns,tsregularitems
    time_off,holiday = [],[]
    (tsstartdate..tsenddate).each do |period_day|
      time_off << Timesheetdatum.timeoff_day_hours(period_day,user,user.companydatum) if columns.include? "Time Off"
      holiday << Timesheetdatum.holiday_hours(period_day,user,user.companydatum) if columns.include? "Holiday"   
    end
    data = fields.map{ |attr| user.send(attr) }
    data[columns.index("Holiday")] =  holiday.compact.reduce(0, :+)
    data[columns.index("Time Off")] = time_off.compact.reduce(0, :+)
    tsregularitems.each do |tsregularitem|
      data[columns.index(tsregularitem.tsitemname)] = Tsperiodhour.order(:tsregularitem_id).where(timesheetdate_id: timesheetdate_id,tsregularitem_id: tsregularitem.id,useraccount_id: user.id).first.try(:tshours).to_f
    end
    data
  end

  def set_bank_table(exportdatum)
    if Date.today.month != exportdatum.month
      table = "csv_timeoffbankhistmons"
    elsif Date.today.year != exportdatum.year
      table = "csv_timeoffbankhistyears"
    else
      table = "csv_timeoffbanks"
    end
    return table
  end

  def set_no_of_records_and_table(exportdatum)
    if Date.today.month != exportdatum.month
      no_of_banks = self.timeoffbankhistmons.count
      table = "csv_timeoffbankhistmons"
    elsif Date.today.year != exportdatum.year
      no_of_banks = self.timeoffbankhistyears.count
      table = "csv_timeoffbankhistyears"
    else
      no_of_banks = self.timeoffbanks.count 
      table = "csv_timeoffbanks"
    end
    return no_of_banks,table
  end

  def fullname
    "#{firstname} #{lastname}"
  end

  def csv_manager_id
    try(:manager).try(:fullname)
  end

  def csv_division_id
    try(:division).try(:name)
  end

  def csv_department_id
    try(:department).try(:name)
  end

  def csv_jobfamily_id
    try(:jobfamily).try(:name)
  end

  def csv_region_id
    try(:companyregion).try(:regionname)
  end

  def address1
    useraccountcontact.try(:address1)
  end

  def csv_timeoffbanks(*args)
    if args.length == 1
      self.timeoffbanks.find_by_timeoffcategory_id(args[0].split('-')[0]).send(args[0].split('-')[1]).try(:round,2) rescue 0.0
    else
      self.timeoffbanks.sort_by(&:created_at).collect{|data| (args[0] == 'timeoffcategory_id') ? data.timeoffcategory.timeoffname : data.send(args[0])}[args[1]].try(:round,2)
    end
  end

  def csv_timeoffbankhistmons(*args)
    if args.length == 1
      self.timeoffbankhistmons.find_by_timeoffcategory_id(args[0].split('-')[0]).send(args[0].split('-')[1]).try(:round,2) rescue 0.0 
    else
      self.timeoffbankhistmons.sort_by(&:created_at).collect{|data| (args[0] == 'timeoffcategory_id') ? data.timeoffcategory.timeoffname : data.send(args[0])}[args[1]].try(:round,2)
    end
  end

  def csv_timeoffbankhistyears(*args)
    if args.length == 1
      self.timeoffbankhistyears.find_by_timeoffcategory_id(args[0].split('-')[0]).send(args[0].split('-')[1]).try(:round,2) rescue 0.0
    else
      self.timeoffbankhistyears.sort_by(&:created_at).collect{|data| (args[0] == 'timeoffcategory_id') ? data.timeoffcategory.timeoffname : data.send(args[0])}[args[1]].try(:round,2)
    end
  end

  def csv_accrualdates
    Acuralrule.joins(:accrualdates).where(accrualdates: {useraccount_id: self.id}, timeoffcategory_id: self.companydatum.timeoffcategories.find_by(timeoffname: "Vacation").id).first.try(:accrualrate).to_f
  end

  def csv_total_projected
    data = Acuralrule.joins(:accrualdates).where(accrualdates: {useraccount_id: self.id}, timeoffcategory_id: self.companydatum.timeoffcategories.find_by(timeoffname: "Vacation").id)
    data.first.try(:accrualrate).to_f * data.count.to_f
  end

  def get_total_accrued(field,exportdatum)
    acuralrules = Acuralrule.where(timeoffcategory_id: field.split('-')[0])
    count = accrualdates.where(accrual_date: exportdatum.startdate..exportdatum.enddate,status: "P",acuralrule_id: acuralrules.map(&:id)).count
    accrualrate_sum = acuralrules.sum(:accrualrate)
    accrued_data = (accrualrate_sum.to_f*count).to_f.abs

    used_data = []
    timeoffrequests1 = timeoffrequests.where('timeoffcategory_id = ? AND reqstatus = ?',field.split('-')[0], 'A').where(reqstart: exportdatum.startdate..exportdatum.enddate)
    timeoffrequests1.each do |timeoffrequest|
      if timeoffrequest.reqend.to_date > exportdatum.enddate
        used_data << (companydatum.company_control.work_week == "S" ? standard_multiple_days_leave(timeoffrequest,exportdatum) : custom_multiple_days_leave(timeoffrequest,exportdatum))
      else
        used_data << timeoffrequest.reqamtstand
      end
    end
    used_data = used_data.inject(){|sum,x| sum + x }

    if field.split('-')[1] == "carryover" || (field.split('-')[1] == "adjustment")
      data = timeoffbankdailyhists.where(timeoffcategory_id: field.split('-')[0]).where(created_at: exportdatum.startdate..exportdatum.enddate).sum(field.split('-')[1].to_sym).try(:round,2)
      if !data.present?
        data = timeoffbankhistmons.where(timeoffcategory_id: field.split('-')[0]).where(created_at: exportdatum.startdate..exportdatum.enddate).sum(field.split('-')[1].to_sym).try(:round,2)
        if !data.present?
          year = whichyear(exportdatum.enddate,companydatum.company_control.start_year_date)
          if year[:banktype] == "C"
            data = timeoffbanks.where(timeoffcategory_id: field.split('-')[0]).first.send(field.split('-')[1]).try(:round,2)
          end
          if year[:banktype] == "H"
            data = timeoffbankhistyears.where(timeoffcategory_id: field.split('-')[0]).first.send(field.split('-')[1]).try(:round,2)
          end
        end
      end
    end
    if field.split('-')[1] == "used"
      data = used_data
    end
    if field.split('-')[1] == "accrued"
      data = accrued_data
    end
    if field.split('-')[1] == "balance"
      data = (accrued_data - (used_data.present? ? used_data : 0.0))
    end
    if field.split('-')[1] == "pending" 
      data = timeoffrequests.where('timeoffcategory_id = ? AND reqstatus = ?',field.split('-')[0], 'P').where('reqstart >= ? AND reqend <= ?',exportdatum.startdate,exportdatum.enddate).sum(:reqamtstand).try(:round,2)
    end
    return data
  end

  def get_timeoffdates(field,exportdatum)
    data = self.timeoffrequests.where(timeoffcategory_id: field.split('-')[0])
    if exportdatum.startdate.present? && exportdatum.enddate.present?
      data.by_date_range(exportdatum.startdate,exportdatum.enddate).collect{|t| request_dates_across_month(t,exportdatum)}.join(', ')
    elsif exportdatum.month.present? && exportdatum.year.present?
      data.by_month_and_year(exportdatum.month,exportdatum.year).collect{|t| t.reqstart.strftime("%Y-%m-%d")+"*"+t.reqend.strftime("%Y-%m-%d")}.join(', ')
    elsif exportdatum.month.present? || exportdatum.year.present?
      data.by_month_or_year(exportdatum.month,exportdatum.year).collect{|t| t.reqstart.strftime("%Y-%m-%d")+"*"+t.reqend.strftime("%Y-%m-%d")}.join(', ')
    end
  end

  def request_dates_across_month timeoffrequest,exportdatum
    if timeoffrequest.reqend.to_date > exportdatum.enddate
      timeoffrequest.reqstart.strftime("%Y-%m-%d")+"*"+exportdatum.enddate.strftime("%Y-%m-%d")
    else
      timeoffrequest.reqstart.strftime("%Y-%m-%d")+"*"+timeoffrequest.reqend.strftime("%Y-%m-%d")
    end
  end

  def approved_and_pending_requests
    pending = timeoffrequests.where(reqstatus:"P").collect{|t| {id: t.id, absence_type: t.timeoffcategory.timeoffname , start: t.reqstart, end: t.reqend, sent: t.created_at, reqamtstand: t.reqamtstand.try(:round,2), comment: t.restext, status: t.reqstatus=="P" ? "Pending" : "Approved"}}
    approved = timeoffrequests.where("DATE(reqstart) > ? AND reqstatus = ?", Date.today, "A").collect{|t| {id: t.id, absence_type: t.timeoffcategory.timeoffname , start: t.reqstart, end:t.reqend, sent: t.created_at, reqamtstand: t.reqamtstand.try(:round,2),comment: t.restext, status: t.reqstatus=="P" ? "Pending" : "Approved"}}
    pending + approved
  end

  def approved_and_pending_requests_for_api
    pending = timeoffrequests.where(reqstatus:"P").collect{|t| {id: t.id, timeoffname: t.timeoffcategory.timeoffname ,timeoffunit: t.timeoffcategory.timeoffunit, startdate: t.reqstart.strftime("%Y-%m-%d"), enddate: t.reqend.strftime("%Y-%m-%d"), starttime: t.reqstart.strftime('%H:%M:%S'), endtime: t.reqend.strftime('%H:%M:%S'), reqamtstand: t.reqamtstand.try(:round,2), mgr_comment: t.restext, user_comment: t.reqreason, status: t.reqstatus=="P" ? "Pending" : "Approved", timeoffcategory_id: t.timeoffcategory.id}}
    approved = timeoffrequests.where("DATE(reqstart) > ? AND reqstatus = ?", Date.today, "A").collect{|t| {id: t.id, timeoffname: t.timeoffcategory.timeoffname,timeoffunit: t.timeoffcategory.timeoffunit,startdate: t.reqstart.strftime("%Y-%m-%d"), enddate: t.reqend.strftime("%Y-%m-%d"), starttime: t.reqstart.strftime('%H:%M'), endtime: t.reqend.strftime('%H:%M'), reqamtstand: t.reqamtstand.try(:round,2), mgr_comment: t.restext, user_comment: t.reqreason, status: t.reqstatus=="P" ? "Pending" : "Approved",timeoffcategory_id: t.timeoffcategory.id}}
    pending + approved
  end

  # Method for Subcribe for mail notification 
  def subscribe
    begin
      response = $mailchimp.lists.subscribe({id: 'ad844adbcb', email: {email: self.email},merge_vars: { fname: self.firstname, lname: self.lastname },:double_optin => false,:update_existing => true})
    rescue
      self.errors.add(:tier, "I think you have not unsubscribe")
    end
  end

  # Method for Unsubscribe for mail notification
  def unsubscribe
    begin
      response = $mailchimp.lists.unsubscribe({id: 'ad844adbcb',email: {email: self.email} })
      self.opt_out = true
      self.opted_out_date = Date.today
    rescue 
      self.errors.add(:tier, "I think you have not subscribe using email confirmation")
    end
  end

  def initial_name
    (firstname.include? " ") ? "#{firstname.split(" ")[0][0].upcase}. #{firstname.split(" ")[1][0].upcase}. #{lastname}" : "#{firstname[0]}. #{lastname}"
  end

  # NOTE::------ Start (Methods below are same as timeoffrequest controller. So changes in the methods of timeoff request controller should be reflects here as well----------#
  def standard_multiple_days_leave timeoffrequest,exportdatum
    cumulativerequested_time = 0
    hours = companydatum.company_control.work_hours_per_day
    (timeoffrequest.reqstart.to_date).upto(exportdatum.enddate){ |date|
      cumulativerequested_time = (cumulativerequested_time + multiple_days_timeoffunit_conversion(timeoffrequest,hours)) if ( !is_weekend?(date) && !is_holiday?(date))
    }
    cumulativerequested_time
  end

  def custom_multiple_days_leave timeoffrequest,exportdatum
    cumulativerequested_time = 0
    (timeoffrequest.reqstart.to_date).upto(exportdatum.enddate){ |date|
      @schedule = get_emp_custom_schedule(date)
      hours = (Time.parse(@schedule.endtime) - Time.parse(@schedule.starttime)).abs / 1.hours rescue 0.0
      cumulativerequested_time = (cumulativerequested_time + multiple_days_timeoffunit_conversion(timeoffrequest,hours)) if (@schedule.try(:isworkday) && !is_holiday?(date))
    }
    cumulativerequested_time
  end

  def single_day_timeoffunit_conversion days_diff,timeoffrequest,hours
    time_diff = (timeoffrequest.reqend - timeoffrequest.reqstart).abs / 1.hours
    if timeoffrequest.timeoffcategory.timeoffunit == "h"
      units = (days_diff * hours).round(2) if time_diff == 0.0
      units = time_diff if time_diff != 0.0
    else
      units = days_diff if time_diff == 0.0
      units = (time_diff / hours.to_f).round(2)  if time_diff != 0.0
    end
    units = 0.0 if hours == 0.0
    return units
  end

  def multiple_days_timeoffunit_conversion timeoffrequest,hours
    if timeoffrequest.timeoffcategory.timeoffunit == "h"
      units = hours
    else
      units = 1 
    end
    units = 0 if hours == 0.0
    return units
  end

  def get_emp_custom_schedule day
    schedule = self.empworkdays.where(weekday: (day.wday-1)==-1 ? 6 : (day.wday-1)).first
    schedule = companydatum.jfworkdays.where("jobfamily_id = ? AND weekday = ? ", self.jobfamily_id, ((day.wday-1)==-1 ? 6 : (day.wday-1)).to_s).first if schedule.nil?
    schedule
  end

  def is_weekend? day
    flag = false
    flag = companydatum.company_control.work_week_off.include? ((day.wday-1)==-1 ? 6 : (day.wday-1))
    return flag
  end

  def is_holiday? day
    companydatum.company_dates.by_region_or_division(self).where("DATE(event_date)=? AND event_type = ?", day,"H").present?
  end
  # NOTE::------ END ----------#
end
