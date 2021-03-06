class AdminAbility
  include CanCan::Ability

  class RegionAdminProxy
    attr_accessor :region_id
    def initialize(region)
      @region_id = region.id if !region.kind_of? Class
    end
  end

  def initialize(person)

    is_config = person.has_role 'chapter_config'

    if is_config # is site manager
      can [:read, :update], Roster::Chapter
      can :manage, Roster::County
      can :manage, Roster::Position
      can :manage, Roster::CellCarrier
      can :manage, Roster::Person
      can :manage, Roster::Role

      can :manage, Scheduler::DispatchConfig
      can :manage, Scheduler::Shift
      can :manage, Scheduler::ShiftGroup
      can :manage, Scheduler::ShiftCategory

      can :manage, Incidents::ReportSubscription
      can :manage, Incidents::PriceListItem
      can :manage, Incidents::CallLog

      can :manage, Logistics::Vehicle


      can :manage, Core::JobLog
      can :manage, MOTD

      can :manage, Partners::Partner

      can :manage, NamedQuery
      can :manage, DataFilter
      can :manage, HomepageLink
      can :manage, Lookup
      can :manage, Delayed::Job

      can :manage, :all
    end

    is_admin = person.has_role 'chapter_admin'
    if is_admin
      chapter = person.chapter_id
      can :read, [Roster::Person, Roster::County, Roster::Position], chapter_id: chapter
      can :impersonate, Roster::Person, chapter_id: chapter
      can :manage, Logistics::Vehicle, chapter_id: chapter
      can :manage, HomepageLink, chapter_id: chapter
      can :new, Incidents::ReportSubscription
      can :manage, Incidents::ReportSubscription, person: {chapter_id: chapter}
      can [:test_report, :send_report, :new], Incidents::ReportSubscription

      can :manage, Incidents::Notifications::Event, chapter_id: chapter
      can :manage, Incidents::Notifications::Role, chapter_id: chapter

      can [:read, :update], Scheduler::DispatchConfig, chapter_id: chapter
      can :read, Incidents::DispatchLog, chapter_id: chapter

      can :manage, Incidents::Territory, chapter_id: chapter

      can :manage, RegionAdminProxy do |region|
        region.region_id.nil? || region.region_id == chapter
      end
    end
  end

end