require 'spec_helper'

describe "Invalid Incident Report", :type => :feature do
  self.use_transactional_fixtures = false
  before do
    grant_role! 'submit_incident_report'

    @chapter = @person.chapter
    @chapter.incidents_report_editable = true
    @chapter.save!
    FactoryGirl.create :incidents_scope, chapter: @person.chapter
  end

  it "Should be submittable" do

    @incident = FactoryGirl.create :raw_incident, chapter: @person.chapter, area: @person.counties.first, date: Date.current

    visit "/incidents/#{@chapter.url_slug}/incidents/#{@incident.incident_number}"

    open_panel "Narrative"
    fill_in 'Narrative*', with: Faker::Lorem.paragraph
    click_button "Update Incident"

    open_panel "Damage Assessment"
    select 'Apartment', from: 'Structure type*'
    fill_in 'Units not livable*', with: 1
    fill_in 'Units livable*', with: 1
    click_button "Update Incident"

    open_panel "Demographics"
    fill_in 'Num adults*', with: 1
    fill_in 'Num children*', with: 1
    fill_in 'Num families*', with: 1
    fill_in 'Num people injured*', with: 1
    fill_in 'Num people hospitalized*', with: 1
    fill_in 'Num people deceased*', with: 1
    click_button "Update Incident"

  end

  def open_panel title
    within "h4", text: title do
      click_link "(edit)"
    end
  end
end
