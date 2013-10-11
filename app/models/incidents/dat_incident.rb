class Incidents::DatIncident < ActiveRecord::Base
  has_paper_trail

  class TimesInCorrectOrder < ActiveModel::Validator
    MESSAGE = "%s must come before %s"
    def validate(record)
      return false unless record.responder_notified and record.responder_arrived and record.responder_departed
      [[:responder_notified, :responder_arrived], [:responder_arrived, :responder_departed]].each do |first_evt, second_evt|
        if record.send( first_evt ) > record.send(second_evt)
          record.errors[second_evt] = MESSAGE % [first_evt.to_s.titleize, second_evt.to_s.titleize]
        end
      end
    end
  end

  belongs_to :incident, class_name: 'Incidents::Incident', inverse_of: :dat_incident
  belongs_to :completed_by, class_name: 'Roster::Person'
  has_many :vehicle_uses, class_name: 'Incidents::VehicleUse', foreign_key: 'incident_id'
  has_many :vehicles, through: :vehicle_uses, class_name: 'Logistics::Vehicle'

  TRACKED_RESOURCE_TYPES = %w(comfort_kits blankets pre-packs toys)

  assignable_values_for :incident_call_type do
    %w(hot cold)
  end

  assignable_values_for :incident_type do
    %w(fire flood police)
  end

  assignable_values_for :structure_type do
    %w(single_family_home apartment sro mobile_home commercial none)
  end

  accepts_nested_attributes_for :incident, update_only: true#, reject_if: :cant_update_incident
  validates :address, :city, :state, :zip, presence: true # :cross_street

  validates :units_affected, :units_minor, :units_major, :units_destroyed, presence: true, numericality: {:greater_than_or_equal_to => 0}
  validates :num_adults, :num_children, :num_families, presence: true, numericality: {:greater_than_or_equal_to => 0}
  validates :num_people_injured, :num_people_hospitalized, :num_people_deceased, presence: true, numericality: {:greater_than_or_equal_to => 0}

  validates :responder_notified, :responder_arrived, :responder_departed, presence: true
  validates_with TimesInCorrectOrder

  validates :completed_by, :vehicle_uses, presence: true

  validates_associated :incident

  serialize :services
  serialize :languages

  after_save :update_incident

  include SerializedColumns
  TRACKED_RESOURCE_TYPES.each do |type_s|
    type = type_s.to_sym
    serialized_accessor :resources, type, :integer
    conditional = ->(obj){ obj.incident.chapter.incidents_resources_tracked_array.include?(type_s)}
    validates_presence_of type, if: conditional
    validates_numericality_of type, greater_than_or_equal_to: 0, allow_blank: false, allow_nil: false, if: conditional
  end

  attr_accessor :search_for_address

  [:responder_notified=, :responder_arrived=, :responder_departed=].each do |sym|
    define_method sym do |val|
      if val.is_a? String
        super Chronic.parse(val)
      else
        super(val)
      end
    end
  end

  def update_incident
    if incident(true)
      incident.update_from_dat_incident
      update_timeline
    end
  end

  [:responder_notified, :responder_arrived, :responder_departed].each do |field|
    define_method :"#{field}=" do |val|
      if val.is_a? String
        time = nil
        begin
          time = Time.zone.parse(val)
        rescue ArgumentError
          errors[field] << "Invalid time format for #{field.to_s.titleize}: #{val}."
        end
        super(time)
      else
        super(val)
      end
    end
  end

  def update_timeline
    {'dat_received' => :responder_notified, 'dat_on_scene' => :responder_arrived, 'dat_departed_scene' => :responder_departed}.each do |event, attr|
      val = self.send(attr)
      if val
        incident.event_logs.where(event: event).first_or_initialize.update_attributes event_time: val
      end
    end
  end

  def units_total
    [units_affected, units_minor, units_major, units_destroyed].compact.sum
  end

  def cant_update_incident
    !(incident.nil? || incident.new_record?)
  end

  def languages= list
    list = list.select(&:present?) if list
    super(list)
  end

end
