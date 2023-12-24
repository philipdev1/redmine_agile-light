# encoding: utf-8
#
# This file is a part of Redmin Agile (redmine_agile) plugin,
# Agile board plugin for redmine
#
# Copyright (C) 2011-2023 RedmineUP
# http://www.redmineup.com/
#
# redmine_agile is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# redmine_agile is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with redmine_agile.  If not, see <http://www.gnu.org/licenses/>.

require File.expand_path('../../test_helper', __FILE__)

module RedmineAgile
  module AgileBoardsControllerTest
    module SpecificTestCase
      def test_get_index_with_filter_issue_id
        compatible_request :get, :index, {
          project_id: 'ecookbook',
          set_filter: '1',
          f: %w(issue_id),
          op: { 'issue_id' => '<=' },
          v: { 'issue_id' => ['2'] },
          c: %w(tracker assigned_to)
        }

        assert_response :success
        assert_equal [1, 2], agile_issues_in_list.map(&:id).sort
      end

      def test_get_index_with_filter_is_private
        project = Project.find(3)
        emodule = EnabledModule.create(project_id: project.id, name: 'agile')

        compatible_request :get, :index, {
          project_id: 'ecookbook',
          set_filter: '1',
          f: %w(is_private),
          op: { 'is_private' => '=' },
          v: { 'is_private' => ['1'] },
          c: %w(tracker assigned_to)
        }

        assert_response :success
        assert_equal [14], agile_issues_in_list.map(&:id)
      ensure
        emodule.destroy
      end

      def test_get_index_with_filter_watcher_id
        issues(:issues_001).set_watcher(users(:users_002))

        compatible_request :get, :index, {
          project_id: 'ecookbook',
          set_filter: '1',
          f: %w(watcher_id),
          op: { 'watcher_id' => '=' },
          v: { 'watcher_id' => ['2'] },
          c: %w(tracker assigned_to)
        }

        assert_response :success
        assert_equal [1], agile_issues_in_list.map(&:id)
      end
    end
  end
end


class AgileBoardsControllerTest < ActionController::TestCase
  fixtures :projects,
           :users,
           :roles,
           :members,
           :member_roles,
           :issues,
           :issue_statuses,
           :issue_relations,
           :versions,
           :trackers,
           :projects_trackers,
           :issue_categories,
           :enabled_modules,
           :enumerations,
           :attachments,
           :workflows,
           :custom_fields,
           :custom_values,
           :custom_fields_projects,
           :custom_fields_trackers,
           :time_entries,
           :journals,
           :journal_details,
           :queries
  fixtures :email_addresses if Redmine::VERSION.to_s > '3.0'

  include(RedmineAgile::AgileBoardsControllerTest::SpecificTestCase) if Redmine::VERSION.to_s > '2.4'

  def setup
    RedmineAgile::TestCase.prepare
    @project_1 = Project.find(1)
    @project_2 = Project.find(5)
    @project_3 = Project.find(3)
    EnabledModule.create(:project => @project_1, :name => 'agile')
    EnabledModule.create(:project => @project_2, :name => 'agile')
    EnabledModule.create(:project => @project_3, :name => 'agile')
    @request.session[:user_id] = 1
  end

  def test_get_index
    # global board
    compatible_request :get, :index
    issues = Issue.where(project: Project.all.select {|p| p.module_enabled?('agile') }.to_a,
                         status_id: IssueStatus.where(is_closed: false))
    assert_equal issues.map(&:id).sort, agile_issues_in_list.map(&:id).sort
    assert_select '.issue-card', issues.count
    assert_select '.issue-card span.fields p.issue-id strong', issues.count
    assert_select '.issue-card span.fields p.name a', issues.count
  end

  def test_get_index_with_project
    compatible_request :get, :index, project_id: @project_1
    issues = Issue.where(project_id: [@project_1] + Project.where(parent_id: @project_1.id)
                                                           .select {|p| p.module_enabled?('agile') }.to_a,
                         status_id: IssueStatus.where(is_closed: false))
    assert_equal issues.map(&:id).sort, agile_issues_in_list.map(&:id).sort
    assert_select '.issue-card', issues.count
    assert_select '.issue-card span.fields p.issue-id strong', issues.count
    assert_select '.issue-card span.fields p.name a', issues.count
  end

  def test_get_index_truncated
    with_agile_settings 'board_items_limit' => 1 do
      compatible_request :get, :index, agile_query_params
      assert_response :success
      assert_select 'div#content p.warning', 1
      assert_select 'td.issue-status-col .issue-card', 1
    end
  end

  def test_limit_for_truncated
    expected_issues = Issue.where(:project_id => [@project_1] + Project.where(:parent_id => @project_1.id).to_a,
                                  :status_id => IssueStatus.where(:is_closed => false))
    with_agile_settings 'board_items_limit' => (expected_issues.count + 1) do
      compatible_request :get, :index, agile_query_params.merge(:f_status => IssueStatus.where(:is_closed => false).pluck(:id))
      assert_response :success
      assert_select 'div#content p.warning', 0
    end
  end if Redmine::VERSION.to_s > '2.4'

  def test_get_index_with_filters
    if Redmine::VERSION.to_s > '2.4'
      compatible_request :get, :index, agile_query_params.merge(:f_status => IssueStatus.where('id != 1').pluck(:id))
    else
      compatible_request :get, :index, agile_query_params.merge(:op => { :status_id => '!' }, :v => { :status_id => ['1'] })
    end
    assert_response :success
    expected_issues = Issue.where(:project_id => [@project_1] + Project.where(:parent_id => @project_1.id).to_a,
                                  :status_id => IssueStatus.where('id != 1'))
    assert_equal expected_issues.map(&:id).sort, agile_issues_in_list.map(&:id).sort
  end

  def test_get_index_with_filter_on_assignee_role
    assignee_params = { :set_filter => '1',
                        :f => ['assigned_to_role', ''],
                        :op => { :assigned_to_role => '=' },
                        :v => { 'assigned_to_role' => ['2'] },
                        :c => ['assigned_to'],
                        :project_id => 'ecookbook' }
    compatible_request :get, :index, assignee_params
    assert_response :success
    members = Member.joins(:roles).where(:project_id => [@project_1]).where('member_roles.role_id = 2').map(&:user_id).uniq
    expected_issues = Issue.where(:project_id => [@project_1]).where(:assigned_to_id => members)
    assert_equal expected_issues.map(&:id).sort, agile_issues_in_list.map(&:id).sort
  end if Redmine::VERSION.to_s > '2.4'

  def create_subissue
    @issue1 = Issue.find(1)
    @subissue = Issue.create!(
      :subject         => 'Sub issue',
      :project         => @issue1.project,
      :tracker         => @issue1.tracker,
      :author          => @issue1.author,
      :parent_issue_id => @issue1.id,
      :fixed_version   => Version.last
    )
  end

  def test_get_index_with_filter_on_parent_tracker
    create_subissue
    compatible_request :get, :index, agile_query_params.merge(
      :op => { :parent_issue_tracker_id => '=' },
      :v => { :parent_issue_tracker_id => [Tracker.find(1).name] },
      :f => [:parent_issue_tracker_id],
      :project_id => Project.order(:id).first.id
    )
    assert_response :success
    assert_equal [@subissue.id], agile_issues_in_list.map(&:id)
  end if Redmine::VERSION.to_s > '2.4'

  def test_get_index_with_filter_on_two_parent_id
    create_subissue
    issue2 = Issue.generate!
    child2 = Issue.generate!(:parent_issue_id => issue2.id)

    compatible_request :get, :index, agile_query_params.merge(
      :op => { :parent_issue_id => '=' },
      :v => { :parent_issue_id => ["#{@issue1.id}, #{issue2.id}"] },
      :f => [:parent_issue_id],
      :project_id => Project.order(:id).first.id
    )
    assert_response :success
    assert_equal [@subissue.id, child2.id].sort, agile_issues_in_list.map(&:id).sort
  end if Redmine::VERSION.to_s > '2.4'

  def test_get_index_with_filter_on_parent_tracker_inversed
    create_subissue
    compatible_request :get, :index, agile_query_params.merge(
      :op => { :parent_issue_tracker_id => '!' },
      :v => { :parent_issue_tracker_id => [Tracker.find(1).name] },
      :f => [:parent_issue_tracker_id],
      :project_id => Project.order(:id).first.id
    )
    assert_response :success
    assert_not_include @subissue.id, agile_issues_in_list.map(&:id)
  end if Redmine::VERSION.to_s > '2.4'

  def test_get_index_with_filter_on_has_subissues
    create_subissue
    compatible_request :get, :index, agile_query_params.merge(
      :op => { :has_sub_issues => '=' },
      :v => { :has_sub_issues => ['yes'] },
      :f => [:has_sub_issues],
      :project_id => Project.order(:id).first.id
    )
    assert_response :success
    assert_equal [@issue1.id], agile_issues_in_list.map(&:id)
  end if Redmine::VERSION.to_s > '2.4'

  def test_get_index_with_filter_and_field_time_in_state
    create_subissue
    columns_group_by = AgileQuery.new.groupable_columns
    columns_group_by.each do |col|
      compatible_request :get, :index, agile_query_params.merge(
        :project_id => Project.order(:id).first.id,
        :group_by => col.name.to_s
      )
      assert_response :success, "Error with group by #{col.name}"
    end
  end if Redmine::VERSION.to_s > '2.4'

  def test_put_update_status
    status_id = 1
    first_issue_id = 1
    second_issue_id = 3
    first_pos = 1
    second_pos = 2
    positions = { first_issue_id.to_s => { 'position' => first_pos }, second_issue_id.to_s => { 'position' => second_pos } }
    compatible_xhr_request :put, :update, :id => first_issue_id, :issue => { :status_id => status_id }, :positions => positions
    assert_response :success
    assert_equal status_id, Issue.find(first_issue_id).status_id
    assert_equal first_pos, Issue.find(first_issue_id).agile_data.position
    assert_equal second_pos, Issue.find(second_issue_id).agile_data.position
    # check js code for update board header
    assert_match '$("table.issues-board thead").html(', @response.body
  end

  def test_put_update_version
    fixed_version_id = 3
    first_issue_id = 1
    second_issue_id = 3
    first_pos = 1
    second_pos = 2
    positions = { first_issue_id.to_s => { 'position' => first_pos }, second_issue_id.to_s => { 'position' => second_pos } }
    compatible_xhr_request :put, :update, :id => first_issue_id, :issue => { :fixed_version_id => fixed_version_id }, :positions => positions
    assert_response :success
    assert_equal fixed_version_id, Issue.find(first_issue_id).fixed_version_id
    assert_equal first_pos, Issue.find(first_issue_id).agile_data.position
    assert_equal second_pos, Issue.find(second_issue_id).agile_data.position
  end

  def test_put_update_assigned
    assigned_to_id = 3
    issue_id = 1
    compatible_xhr_request :put, :update, :id => issue_id, :issue => { :assigned_to_id => assigned_to_id }
    assert_response :success
    assert_equal assigned_to_id, Issue.find(issue_id).assigned_to_id
  end

  def test_get_index_with_all_fields
    compatible_request :get, :index, agile_query_params.merge(:f => AgileQuery.available_columns.map(&:name))
    assert_response :success
  end

  def test_short_card_for_closed_issue
    with_agile_settings 'hide_closed_issues_data' => '1' do
      closed_status = IssueStatus.where(:is_closed => true).pluck(:id)
      closed_issues = Issue.where(:status_id => closed_status)
      project = closed_issues.first.project

      # get :index, agile_query_params.merge(:f_status => closed_status)
      if Redmine::VERSION.to_s > '2.4'
        compatible_request :get, :index, agile_query_params.merge(:f_status => closed_status)
      else
        compatible_request :get, :index, agile_query_params.merge('f' => [''])
      end

      assert_response :success
      assert_select '.closed-issue', project.issues.where(:status_id => IssueStatus.where(:is_closed => true)).count
    end
  end

  def test_get_tooltip_for_issue
    issue = Issue.where(:status_id => IssueStatus.where(:is_closed => true)).first
    compatible_request :get, :issue_tooltip, :id => issue.id
    assert_response :success
    assert_select 'a.issue', 1
    assert_select 'strong', 6
    assert_match issue.status.name, @response.body
  end

  def test_empty_node_for_tooltip
    with_agile_settings 'hide_closed_issues_data' => '1' do
      closed_status = IssueStatus.where(:is_closed => true).pluck(:id)
      if Redmine::VERSION.to_s > '2.4'
        compatible_request :get, :index, agile_query_params.merge(:f_status => closed_status)
      else
        compatible_request :get, :index, agile_query_params.merge('f' => [''])
      end
      assert_select 'span.tip', { :text => '' }
    end
  end

  def test_setting_for_closed_issues
    with_agile_settings 'hide_closed_issues_data' => '0' do
      closed_issues = Issue.where(:status_id => IssueStatus.where(:is_closed => true))
      project = closed_issues.first.project
      compatible_request :get, :index, agile_query_params.merge('f' => [''])
      assert_response :success
      assert_select '.closed-issue', 0
    end
  end

  def test_index_with_js_format
    with_agile_settings 'hide_closed_issues_data' => '1' do
      closed_issues = Issue.where(:status_id => IssueStatus.where(:is_closed => true))
      project = closed_issues.first.project
      compatible_xhr_request :get, :index, agile_query_params.merge('f' => [''], :format => :js)
      assert_response :success
      assert_match "$('.tooltip').mouseenter(callGetToolTipInfo)", @response.body
    end
  end

  def test_get_index_with_day_in_state_and_parent_group
    compatible_request :get, :index, agile_query_params.merge(:c => ['day_in_state'], :group_by => 'parent')
    assert_response :success
  end

  def test_assinged_to_and_in_state_in_index
    issue1 = Issue.find(1)
    issue2 = Issue.create!(
      :subject         => 'Test assigned_to with day in state',
      :project         => issue1.project,
      :tracker         => issue1.tracker,
      :author          => issue1.author,
      :fixed_version   => Version.last
    )
    compatible_request :get, :index, agile_query_params.merge(:c => ['day_in_state'], :group_by => 'parent')
    assigned_to_id = 3
    issue_id = issue2.id
    compatible_xhr_request :put, :update, :id => issue_id, :issue => { :assigned_to_id => assigned_to_id }
    assert_response :success
    issue2.reload
    assert_equal assigned_to_id, issue2.assigned_to_id
  end

  def test_index_with_relations_relates
    create_issue_relation
    compatible_request :get, :index, agile_query_params.merge(:f_status => IssueStatus.pluck(:id), :op => { :status_id => '*', :relates => '*' }, :f => ['relates'])
    assert_response :success
    assert_equal [1, 7, 8], agile_issues_in_list.map(&:id).sort
  end if Redmine::VERSION.to_s > '2.4'

  def test_index_with_relations_blocked
    create_issue_relation

    compatible_request :get, :index, agile_query_params.merge(:f_status => IssueStatus.pluck(:id), :op => { :status_id => '*', :blocked => '*' }, :f => ['blocked'])
    assert_response :success
    assert_equal [2, 11], agile_issues_in_list.map(&:id).sort
  end if Redmine::VERSION.to_s > '2.4'

  def test_list_of_attributes_on_update_status
    params = agile_query_params.merge(:c => ['project', 'day_in_state'], :group_by => 'parent')
    params.delete(:project_id)
    compatible_request :get, :index, params
    assert_response :success
    assert_select 'p.project'
    compatible_request :put, :update, :issue => { :status_id => 2 }, :id => 1
    assert_select 'p.project', { :text => @project_1.to_s }
  end

  def test_day_in_state_when_change_status
    @request.session[:agile_query] = {}
    @request.session[:agile_query][:column_names] = ['project', 'day_in_state']
    issue = Issue.find(1)
    compatible_request :put, :update, :issue => { :status_id => 2 }, :id => 1
    issue.reload
    assert_response :success
    assert_equal 2, issue.status_id
    assert_select 'p.attributes', /0.hours/
  end if Redmine::VERSION.to_s > '2.4'

  def test_global_query_and_project_board
    query = AgileQuery.create(:name => 'global', :column_names => ['project'], :visibility => 2, :options => { :is_default => true })
    compatible_request :get, :index, :project_id => 1
    assert_select 'p.project', { :count => 0, :text => Project.find(2).to_s }
  end if Redmine::VERSION.to_s > '2.4'

  def test_total_estimated_hours_for_status
    Setting.stubs(:display_subprojects_issues?).returns(false) if Redmine::VERSION.to_s >= '4.0'
    Issue.find(1, 2, 3).each do |issue|
      issue.estimated_hours = 10
      issue.save
    end

    compatible_request :get, :index, agile_query_params.merge(c: ['estimated_hours'],
                                                              f: [:issue_id],
                                                              op: { issue_id: '><' },
                                                              v: { issue_id: [1, 3] })

    assert_response :success

    assert_select 'thead tr th span.hours', { count: 1, text: '20.00h' } # status_id == 1
    assert_select 'thead tr th span.hours', { count: 1, text: '10.00h' } # status_id == 2
  end

  def test_get_index_with_checklist
    # global board
    issue1 = issue_with_checklist

    compatible_request :get, :index, agile_query_params.merge(:c => ['checklists'], :project_id => nil)
    assert_response :success
    # check checklist nodes
    assert_select "#checklist_#{issue1.id}"
    issue1.checklists.each do |checklist|
      assert_select "#checklist_item_#{checklist.id}", :text => checklist.subject
    end
  end if RedmineAgile.use_checklist?

  def test_get_index_without_checklist
    issue1 = issue_with_checklist
    compatible_request :get, :index, :c => []
    assert_response :success
    # check checklist nodes
    assert_select "#checklist_#{issue1.id}", :count => 0
    issue1.checklists.each do |checklist|
      assert_select "#checklist_item_#{checklist.id}", :count => 0
    end
  end if RedmineAgile.use_checklist?

  def test_get_index_with_project_with_checklist
    issue1 = issue_with_checklist
    compatible_request :get, :index, agile_query_params.merge(:c => ['checklists'], :project_id => issue1.project)
    assert_response :success
    # check checklist nodes
    assert_select "#checklist_#{issue1.id}"
    issue1.checklists.each do |checklist|
      assert_select "#checklist_item_#{checklist.id}", :text => checklist.subject
    end
  end if RedmineAgile.use_checklist?

  def test_get_index_with_project_without_checklist
    issue1 = issue_with_checklist
    compatible_request :get, :index, agile_query_params.merge(:project_id => issue1.project, :c => [])
    assert_response :success
    # check checklist nodes
    assert_select "#checklist_#{issue1.id}", :count => 0
    issue1.checklists.each do |checklist|
      assert_select "#checklist_item_#{checklist.id}", :count => 0
    end
  end if RedmineAgile.use_checklist?

  def test_get_index_check_quick_edit_without_permission
    role = Role.find(2)
    role.permissions << :veiw_issues
    role.permissions << :view_agile_queries
    role.permissions.delete(:edit_issues)
    role.save
    @request.session[:user_id] = 3

    compatible_request :get, :index, :project_id => @project_1
    issues = Issue.where(:project_id => [@project_1], :status_id => IssueStatus.where(:is_closed => false))
    assert_response :success
    assert_select '.issue-card', agile_issues_in_list.count
    assert_select '.issue-card .quick-edit-card a', :count => 0
  end

  def test_last_comment_on_issue_cart
    issue = @project_1.issues.open.first
    text_comment = 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus in blandit ex. Donec vitae urna quis tortor tempor mollis.'
    comment = Journal.new(:notes => text_comment, :user_id => 1)
    issue.journals << comment
    params = agile_query_params.merge(:c => ['project', 'last_comment'], :group_by => 'parent')
    compatible_request :get, :index, params
    assert_response :success
    assert_select 'span.last-comment', :text => text_comment.truncate(100)
    compatible_request :put, :update, :issue => { :status_id => 2 }, :id => issue.id
    assert_select 'span.last-comment', :text => text_comment.truncate(100)
  end if Redmine::VERSION.to_s > '2.4'

  def test_show_sp_value_on_issue_cart
    with_agile_settings 'estimate_units' => 'story_points', 'story_points_on' => '1' do
      issues = @project_1.issues.open.first(3)
      issues.each do |issue|
        issue.agile_data.story_points = issue.id * 10
        issue.save
      end
      params = agile_query_params.merge(:c => ['story_points'])
      compatible_request :get, :index, params
      IssueStatus.where(:id => @project_1.issues.open.joins(:status).pluck(:status_id).uniq).each do |status|
        sp_sum = @project_1.issues.eager_load(:agile_data).where(:status_id => status.id).sum("#{AgileData.table_name}.story_points")
        next unless sp_sum.to_i > 0
        assert_select "th[data-column-id='#{status.id}'] span.hours", :text =>"#{sp_sum}sp"
      end
      issues.each do |issue|
        assert_select ".issue-card[data-id='#{issue.id}'] span.fields p.issue-id span.hours", :text =>"(#{issue.story_points}sp)"
      end
      # check story_points in available_columns for query
      assert_select 'input[value="story_points"]'
    end
  end if Redmine::VERSION.to_s > '2.4'

  def test_show_sp_with_estimated_hours_on_issue_cart
    Setting.stubs(:display_subprojects_issues?).returns(false)

    with_agile_settings 'estimate_units' => 'story_points', 'story_points_on' => '1' do
      issues = @project_1.issues.open.first(3)
      issues.each do |issue|
        issue.agile_data.story_points = issue.id * 10
        issue.estimated_hours = issue.id * 2
        issue.save
      end

      compatible_request :get, :index, agile_query_params.merge(c: %w(story_points estimated_hours))

      # Should show estimated time and story points in the board header
      IssueStatus.where(id: @project_1.issues.open.joins(:status).pluck(:status_id).uniq).each do |status|
        column_issues = @project_1.issues.eager_load(:agile_data).where(status_id: status.id)
        sp_sum = column_issues.to_a.sum { |issue| issue.story_points.to_i }
        estimated_hours = column_issues.to_a.sum { |issue| issue.estimated_hours.to_i }
        values = []
        values.push('%.2fh' % estimated_hours) if estimated_hours.to_i > 0
        values.push("#{sp_sum}sp") if sp_sum.to_i > 0
        if values.present?
          assert_select "th[data-column-id='#{status.id}'] span.hours", text: values.join('/')
        end
      end

      # Should show estimated time and story points on a card
      issues.each do |issue|
        assert_select ".issue-card[data-id='#{issue.id}'] span.fields p.issue-id span.hours",
                      text: "(#{"%.2fh" % issue.estimated_hours.to_f}/#{issue.story_points}sp)"
      end
    end
  end

  def test_index_for_estimated_values_by_default
    prepare_issues_with_points_and_estimated_hours
    compatible_request :get, :index
    should_not_show_estimated_hours
    should_not_show_story_points
  end

  def test_index_for_estimated_values_with_enabled_options
    prepare_issues_with_points_and_estimated_hours
    compatible_request :get, :index, agile_query_params.merge(c: %w(story_points estimated_hours))
    should_show_estimated_hours
    should_not_show_story_points
  end

  def test_index_for_estimated_values_with_estimate_units
    with_agile_settings 'estimate_units' => RedmineAgile::ESTIMATE_STORY_POINTS do
      prepare_issues_with_points_and_estimated_hours
      compatible_request :get, :index
      should_not_show_estimated_hours
      should_not_show_story_points
    end
  end

  def test_index_for_estimated_values_with_estimate_units_and_enabled_options
    with_agile_settings 'estimate_units' => RedmineAgile::ESTIMATE_STORY_POINTS, 'story_points_on' => '1' do
      prepare_issues_with_points_and_estimated_hours
      compatible_request :get, :index, agile_query_params.merge(c: %w(story_points estimated_hours))
      should_show_estimated_hours
      should_show_story_points
    end
  end

  def test_index_for_estimated_values_with_story_points_off
    with_agile_settings 'story_points_on' => '0' do
      prepare_issues_with_points_and_estimated_hours
      compatible_request :get, :index
      should_not_show_estimated_hours
      should_not_show_story_points
    end
  ensure
    Setting.plugin_redmine_agile.delete('story_points_on')
  end

  def test_index_for_estimated_values_with_story_points_off_and_enabled_options
    with_agile_settings 'story_points_on' => '0' do
      prepare_issues_with_points_and_estimated_hours
      compatible_request :get, :index, agile_query_params.merge(c: %w(story_points estimated_hours))
      should_show_estimated_hours
      should_not_show_story_points
    end
  ensure
    Setting.plugin_redmine_agile.delete('story_points_on')
  end

  def test_index_for_estimated_values_with_story_points_on
    with_agile_settings 'story_points_on' => '1' do
      prepare_issues_with_points_and_estimated_hours
      compatible_request :get, :index
      should_not_show_estimated_hours
      should_not_show_story_points
    end
  ensure
    Setting.plugin_redmine_agile.delete('story_points_on')
  end

  def test_index_for_estimated_values_with_story_points_on_and_enabled_options
    with_agile_settings 'story_points_on' => '1' do
      prepare_issues_with_points_and_estimated_hours
      compatible_request :get, :index, agile_query_params.merge(c: %w(story_points estimated_hours))
      should_show_estimated_hours
      should_show_story_points
    end
  ensure
    Setting.plugin_redmine_agile.delete('story_points_on')
  end

  def test_quick_add_comment_button
    with_agile_settings 'allow_inline_comments' => 1 do
      compatible_request :get, :index, agile_query_params
      assert_response :success
      assert_select '.quick-edit-card img[alt="Comment"]'
    end
  end if Redmine::VERSION.to_s > '2.4'

  def test_quick_add_comment_form
    compatible_request :get, :inline_comment, :id => @project_1.issues.open.first
    assert_response :success
    assert_select 'textarea'
    assert_select 'button'
  end if Redmine::VERSION.to_s > '2.4'

  def test_quick_add_comment_update
    issue = @project_1.issues.open.first
    compatible_request :put, :update, :issue => { :notes => 'new comment!!!' }, :id => issue
    assert_response :success
    assert_select '.last_comment', :text => 'new comment!!!'
  end if Redmine::VERSION.to_s > '2.4'

  
  def test_card_for_new_issue
  with_agile_settings "allow_create_card" => 1 do
  statuses = IssueStatus.all
  compatible_request :get, :index, {
  "set_filter"=>"1", :project_id => @project_1, :f_status => statuses.map(&:id) }
  assert_select '.add-issue input.new-card__input', 0
  end
  end if Redmine::VERSION.to_s > '2.4'
  

  def test_on_auto_assign_on_move
    with_agile_settings 'auto_assign_on_move' => '1' do
      @request.session[:user_id] = 2
      issue = Issue.find(1)

      user = issue.project.users.first
      @request.session[:user_id] = user.id

      assert_nil issue.assigned_to
      compatible_request :put, :update, :issue => { :status_id => 2 }, :id => 1
      issue.reload
      assert_response :success
      assert_equal 2, issue.status_id
      assert_equal user, issue.assigned_to
    end
  end

  def test_off_auto_assign_on_move
    with_agile_settings 'auto_assign_on_move' => '0' do
      issue = Issue.find(1)

      user = issue.project.users.first
      @request.session[:user_id] = user.id

      assert_nil issue.assigned_to
      compatible_request :put, :update, :issue => { :status_id => 2 }, :id => 1
      issue.reload
      assert_response :success
      assert_equal 2, issue.status_id
      assert_nil issue.assigned_to
    end
  end

  def test_off_auto_assign_on_move_by_sorting
    with_agile_settings 'auto_assign_on_move' => '1' do
      @request.session[:user_id] = 2
      issue = Issue.find(1)

      user = issue.project.users.first
      @request.session[:user_id] = user.id

      assert_nil issue.assigned_to
      compatible_request :put, :update, :issue => { :status_id => issue.status_id }, :id => 1
      issue.reload
      assert_response :success
      assert_nil issue.assigned_to
    end
  end

  def test_option_for_select_current_version
    @request.session[:user_id] = 1
    compatible_request :get, :index, :project_id => @project_1
    assert_response :success
    assert_match 'current_version', response.body
  end if Redmine::VERSION.to_s > '2.4'

  def test_filter_by_current_version
    @request.session[:user_id] = 1
    compatible_request :get, :index, :project_id => @project_1, 'v' => { 'fixed_version_id' => ['current_version'] },
                                                                'set_filter' => '1', 'f' => ['fixed_version_id'],
                                                                'op' => { 'fixed_version_id' => '=' }
    assert_response :success
    current_version = @project_1.shared_versions.order(:effective_date).first
    issue = @project_1.issues.first
    issue.fixed_version = current_version
    issue.save
    assert agile_issues_in_list.all? { |i| i.fixed_version == current_version }
  end if Redmine::VERSION.to_s > '2.4'

  def test_filter_by_current_version_closed
    @request.session[:user_id] = 1
    current_version = @project_1.shared_versions.order(:effective_date).first
    current_version.status = 'closed'
    current_version.save

    compatible_request :get, :index, :project_id => @project_1, 'v' => { 'fixed_version_id' => ['current_version'] },
                                                                'set_filter' => '1', 'f' => ['fixed_version_id'],
                                                                'op' => { 'fixed_version_id' => '=' }
    assert_response :success
    issue = @project_1.issues.first
    issue.fixed_version = current_version
    issue.save
    assert agile_issues_in_list.all?{ |i| i.fixed_version != current_version }
    # check set filter for current version
    assert_match 'addFilter("fixed_version_id", "=", ["current_version"])', response.body
  end if Redmine::VERSION.to_s > '2.4'

  private

  def agile_query_params
    { :set_filter => '1', :f => ['status_id', ''], :op => { :status_id => 'o' }, :c => ['tracker', 'assigned_to'], :project_id => 'ecookbook' }
  end

  def create_issue_relation
    IssueRelation.delete_all
    IssueRelation.create!(:relation_type => 'relates', :issue_from => Issue.find(1), :issue_to => Issue.find(7))
    IssueRelation.create!(:relation_type => 'relates', :issue_from => Issue.find(8), :issue_to => Issue.find(1))
    IssueRelation.create!(:relation_type => 'blocks', :issue_from => Issue.find(1), :issue_to => Issue.find(11))
    IssueRelation.create!(:relation_type => 'blocks', :issue_from => Issue.find(12), :issue_to => Issue.find(2))
  end

  def issue_with_checklist
    issue1 = Issue.find(1)
    chk1 = issue1.checklists.create(:subject => 'TEST1', :position => 1)
    chk2 = issue1.checklists.create(:subject => 'TEST2', :position => 2)
    issue1
  end if RedmineAgile.use_checklist?

  def prepare_issues_with_points_and_estimated_hours
    issues = @project_1.issues.open.first(3)
    issues.each do |issue|
      issue.agile_data.story_points = issue.id * 10
      issue.estimated_hours = issue.id * 2
      issue.save
    end
  end

  def should_show_estimated_hours
    assert_select "th span.hours", text: /.+h/
    assert_select ".issue-card span.fields p.issue-id span.hours", text: /.+h/
  end

  def should_not_show_estimated_hours
    assert_select "th span.hours", { count: 0, text: /.+h/ }
    assert_select ".issue-card span.fields p.issue-id span.hours", { count: 0, text: /.+h/ }
  end

  def should_show_story_points
    assert_select "th span.hours", text: /.+sp/
    assert_select ".issue-card span.fields p.issue-id span.hours", text: /.+sp/
  end

  def should_not_show_story_points
    assert_select "th span.hours", { count: 0, text: /.+sp/ }
    assert_select ".issue-card span.fields p.issue-id span.hours", { count: 0, text: /.+sp/ }
  end
end
