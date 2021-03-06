require 'spec_helper'

describe "Incident Responders Console", :type => :feature do

  after :each do
    ActionMailer::Base.deliveries.clear
  end

  before do
    grant_role! :incidents_admin
    @chapter = @person.chapter
    @chapter.incidents_enable_dispatch_console = true
    @chapter.save!
    FactoryGirl.create :incidents_scope, chapter: @person.chapter
    county = @person.counties.first

    @responders = (1..3).map{|x|
        FactoryGirl.create :person, chapter: @chapter, last_name: "Responder#{x}", counties: @person.counties, positions: @person.positions
    }

    @flex_responder = @responders.first
    flex_schedule = Scheduler::FlexSchedule.new(id: @flex_responder.id)
    flex_schedule.update_attributes Scheduler::FlexSchedule.available_columns.map{|s| {s => true}}.reduce(&:merge)

    @committed_responder = @responders.second
    @committed_responder.update_attributes work_phone_carrier: FactoryGirl.create( :cell_carrier)
    group = FactoryGirl.create :shift_group, chapter: @chapter
    shift = FactoryGirl.create :shift, shift_groups: [group], county: county, positions: @committed_responder.positions
    assignment = FactoryGirl.create :shift_assignment, person: @committed_responder, shift: shift, date: @chapter.time_zone.today

    @incident = FactoryGirl.create :raw_incident, chapter: @person.chapter, area: county, date: Date.current
    @log = FactoryGirl.create :event_log, chapter: @chapter, person: @person, incident: @incident

    @outbound_messages = outbound_messages = []
    client = double(:sms_client)
    allow(client).to receive :send_message do |message|
      #puts "SMS: #{message.message}"
      outbound_messages << message.message
    end
    Incidents::SMSClient.stub(new: client)
    Bitly.stub(client: double(:shorten => double(short_url: "https://short.url")))
  end
    
  it "Should be submittable" do
    ApplicationController.stub current_user: @person
    visit "/incidents/#{@chapter.url_slug}/incidents/#{@incident.incident_number}"

    click_on "Responders"
    click_on "Show Responders Console"

    expect(page).to have_text(@incident.address)
    expect(page).to have_text(@flex_responder.full_name)
    expect(page).to have_text(@committed_responder.full_name)

    within 'tr', text: @committed_responder.full_name do
      click_link "Assign"
    end
    select "Team Lead", from: 'Response*'
    check "Send assignment sms"
    check "Send assignment email"
    click_button "Save Assignment"
    expect(find(".assigned-table")).to have_text(@committed_responder.full_name)

    within 'tr', text: @flex_responder.full_name do
      click_link "Assign"
    end
    select "Not Available", from: "Response*"
    click_button "Save Assignment"
    expect(find(".assigned-table")).not_to have_text(@flex_responder.full_name)
  end

  it "Should support SMS recruitments" do
    @chapter.update_attributes :incidents_enable_messaging => true
    visit "/incidents/#{@chapter.url_slug}/incidents/#{@incident.incident_number}/responders"

    # Set recruit message
    message = Faker::Lorem.sentence
    click_link "Empty"
    find(".editable-input input").set message
    find(".editable-buttons i.glyphicon-ok").click
    expect(page).to have_text message
    
    within 'tbody.responders-list tr', text: @committed_responder.full_name do
      click_link "Send SMS"
    end

    expect(find("tbody.responders-list tr", text: @committed_responder.full_name)).to have_text "Message Sent"
    expect(last_message).to include(message)
    handle_sms @committed_responder, "yes"

    visit(current_path) # Trigger a refresh, since the auto-update won't work here
    expect(find("tbody.responders-list tr", text: @committed_responder.full_name)).to have_text "Available"

    handle_sms @committed_responder, "no"
    visit(current_path)
    expect(find("tbody.not-available tr", text: @committed_responder.full_name)).to have_text "Not Available"
  end

  it "Should support SMS messaging" do
    FactoryGirl.create :responder_assignment, person: @committed_responder, role: "responder", incident: @incident

    @chapter.update_attributes :incidents_enable_messaging => true
    visit "/incidents/#{@chapter.url_slug}/incidents/#{@incident.incident_number}/responders"

    click_link "Message All"
    message = Faker::Lorem.sentence
    fill_in "Message*", with: (message)

    #sleep 2
    #pp page.driver.console_messages
    #pp page.evaluate_script("window.responderMessagesController.toString()")

    expect(find(".num-characters")).to have_text((message.length - 1).to_s)

    click_button "Send Message"
    expect(page).not_to have_selector('#edit-modal', visible: true)
    expect(last_message).to include(message)

    # Send a direct message
    within ".assigned-table tr", text: @committed_responder.full_name do
      click_link "Actions"
      click_link "Send Message"
    end

    choose "Map Link"
    click_button "Send Message"
    close_modal
    expect(last_message).to include("short.url")

    # Show an incoming message
    message = Faker::Lorem.sentence
    handle_sms @committed_responder, message
    visit current_path
    expect(page).to have_text(message.first 15)

    within '.incoming-table' do
      click_link "View"
    end

    open_modal
    #screenshot_and_open_image
    click_button "Acknowledge"
    close_modal
    expect(Incidents::ResponderMessage.last.acknowledged).to eq(true)
  end

  it "should allow updating responder statuses" do
    ra = FactoryGirl.create :responder_assignment, person: @committed_responder, role: "responder", incident: @incident

    @chapter.update_attributes :incidents_enable_messaging => true
    visit "/incidents/#{@chapter.url_slug}/incidents/#{@incident.incident_number}/responders"

    within ".assigned-table tr", text: @committed_responder.full_name do
      expect(page).to have_text "Assigned at"

      click_link "Actions"
      click_link "Mark Dispatched"

      expect(page).to have_text "Dispatched at"
      expect(ra.reload.dispatched_at).not_to be_nil

      click_link "Actions"
      click_link "Mark On Scene"

      expect(page).to have_text "On Scene at"
      expect(ra.reload.on_scene_at).not_to be_nil

      click_link "Actions"
      click_link "Mark Departed Scene"

      expect(page).to have_text "Departed at"
      expect(ra.reload.departed_scene_at).not_to be_nil
    end
  end

  def handle_sms from, body
    message = Incidents::ResponderMessage.create! person: from, message: body, chapter: @chapter
    reply = Incidents::ResponderMessageService.new(message).reply
    reply.message
  end

  def last_message
    @outbound_messages.last
  end

  def clear_messages
    @outbound_messages.clear
  end

  def close_modal
    expect(page).not_to have_selector('#edit-modal', visible: true)
  end

  def open_modal
    expect(page).to have_selector('#edit-modal', visible: true)
  end
  
end