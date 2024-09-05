# Take a collection of Jira issues that are assigned to the current user and are not in a Done status, and add them to the top of mind list.
# Use the label to create a view in Jira that shows the top of mind issues.

require_relative 'jira'
require 'common'
require 'active_support/time'

def gen_top_of_mind
    by_priority = {}
    Jira::Issues.search("assignee in (currentUser()) AND statusCategory != Done AND status != Testing AND status != Approved AND sprint in openSprints()").each do |issue|
        # Exclude epics
        if issue['fields']['issuetype']['name'] == 'Epic'
            info "#{issue['key']} (#{issue['fields']['summary']}) is an epic! Not adding to top of mind"
            next
        end
        priority = issue['fields']['priority']['name']
        # Ensure issue is not blocked
        if issue['fields']['issuelinks'].any?{|link| link['type']['name'] == 'Blocks' && !link['inwardIssue'].nil? && link['inwardIssue']['fields']['status']['name'] != 'Done'}
            info "#{issue['key']} is blocked! Not adding to top of mind"
            next
        end
        last_status_change = Time.parse(issue['fields']['statuscategorychangedate'])
        if TempStorage.is_stored?("tom-#{issue['key']}") && last_status_change < TempStorage.get_store_time("tom-#{issue['key']}")
            info "#{issue['key']} (#{issue['fields']['summary']}) is already (or recently) in top of mind! Not adding to top of mind. Last status change: #{last_status_change.strftime('%m/%d/%Y %H:%M:%S')}"
            next
        end
        by_priority[priority] ||= []
        by_priority[priority] << issue
    end
    # Sort by priority
    by_priority = by_priority.sort_by do |priority, issues|
        case priority
        when "Highest" then 1
        when "High" then 2
        when "Medium" then 3
        when "Low" then 4
        when "Lowest" then 5
        else raise "Unknown priority #{priority}"
        end
    end.to_h
    top_of_mind = []
    count_by_priority = {}
    by_priority.each do |priority, issues|
        count_by_priority[priority] = 0
    end
    info "Found #{by_priority.values.flatten.length} potential issues for top of mind"
    quota = 5
    while quota > 0
        found = false
        count_by_priority.each do |priority, count|
            next if quota <= 0
            next if by_priority[priority].length <= count
            count += 1
            quota -= 1
            count_by_priority[priority] = count
            found = true
        end
        break unless found
    end
    by_priority.each do |priority, issues|
        count = count_by_priority[priority]
        info "Adding #{count} #{priority} issues to top of mind"
        top_of_mind += issues.shuffle[0...count]
    end
    remove_old_top_of_mind(exlude: top_of_mind.map{|issue| issue['key']})
    top_of_mind.each do |issue|
        next if issue['fields']['labels'].include?('top-of-mind')
        Jira::Issues.add_label(issue['key'], 'top-of-mind')
        TempStorage.store "tom-#{issue['key']}", 1, expiry: 7.days
        info "Added #{issue['key']} (#{issue['fields']['summary']}) to top of mind"
    end
end

def remove_old_top_of_mind(exlude: [])
    Jira::Issues.search("assignee in (currentUser()) AND labels = 'top-of-mind'").each do |issue|
        next if exlude.include?(issue['key'])
        info "Removing label from #{issue['key']} (#{issue['fields']['summary']})"
        Jira::Issues.remove_label(issue['key'], 'top-of-mind')
    end
end

gen_top_of_mind
