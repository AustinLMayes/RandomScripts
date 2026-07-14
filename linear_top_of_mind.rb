require 'common'
require 'active_support/time'

TEAM = "CCENG"
TOM_LABEL = "top-of-mind"
QUOTA = 5
PRIORITY_ORDER = { "Urgent" => 1, "High" => 2, "Medium" => 3, "Low" => 4, "No priority" => 5 }.freeze

def gen_top_of_mind
  label_id = Linear::Labels.id(TOM_LABEL, team_key: TEAM)
  error "No '#{TOM_LABEL}' label in Linear team #{TEAM}; create it first" if label_id.nil?

  by_priority = {}
  filter = {
    team: { key: { eq: TEAM } },
    state: { type: { nin: %w[completed canceled] } },
    or: [{ assignee: { isMe: { eq: true } } }, { updatedAt: { lt: "-P30D" } }]
  }
  Linear::Issues.search(filter).each do |issue|
    next unless (issue.dig("children", "nodes") || []).empty?
    next if issue.dig("state", "name").to_s.include?("QA")
    priority = issue["priorityLabel"] || "No priority"
    key = issue["identifier"]
    last_change = Time.parse(issue["updatedAt"].to_s)
    if TempStorage.is_stored?("tom-#{key}") && last_change < TempStorage.get_store_time("tom-#{key}")
      info "#{key} (#{issue["title"]}) already recently in top of mind; skipping"
      next
    end
    by_priority[priority] ||= []
    by_priority[priority] << issue
  end

  by_priority = by_priority.sort_by { |priority, _| PRIORITY_ORDER[priority] || 99 }.to_h
  count_by_priority = Hash.new(0)
  info "Found #{by_priority.values.flatten.length} potential issues for top of mind"

  quota = QUOTA
  while quota > 0
    found = false
    by_priority.each do |priority, issues|
      next if quota <= 0 || issues.length <= count_by_priority[priority]
      count_by_priority[priority] += 1
      quota -= 1
      found = true
    end
    break unless found
  end

  top_of_mind = []
  by_priority.each do |priority, issues|
    count = count_by_priority[priority]
    info "Adding #{count} #{priority} issues to top of mind"
    top_of_mind += issues.shuffle[0...count]
  end

  remove_old_top_of_mind(label_id, exclude: top_of_mind.map { |i| i["identifier"] })
  top_of_mind.each do |issue|
    next if (issue.dig("labels", "nodes") || []).any? { |l| l["name"] == TOM_LABEL }
    Linear::Issues.add_label(issue["identifier"], label_id)
    TempStorage.store "tom-#{issue["identifier"]}", 1, expiry: 7.days
    info "Added #{issue["identifier"]} (#{issue["title"]}) to top of mind"
  end
end

def remove_old_top_of_mind(label_id, exclude: [])
  Linear::Issues.search({ labels: { some: { name: { eq: TOM_LABEL } } } }).each do |issue|
    next if exclude.include?(issue["identifier"])
    info "Removing #{TOM_LABEL} from #{issue["identifier"]} (#{issue["title"]})"
    Linear::Issues.remove_label(issue["identifier"], label_id)
  end
end

gen_top_of_mind
