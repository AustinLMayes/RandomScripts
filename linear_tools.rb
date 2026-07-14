require 'common'

TEAM = "CCENG"
PARENT = nil

def bulk_create
  data = []
  File.open(File.join(__dir__, 'jira_data.txt')).each do |line|
    if line.start_with?("   ") || line.strip.empty?
      data[-1][:description] += line.strip.gsub("[]", "[link]") + "\n" unless data.empty?
    else
      data << { parent: line.strip, children: [], description: "" }
    end
  end

  parent_id = PARENT ? Linear::Issues.get(PARENT)["id"] : nil

  data.each do |item|
    issue = Linear::Issues.create(team_key: TEAM, title: item[:parent], description: item[:description], parent_id: parent_id)
    info "Created #{issue["identifier"]} - #{item[:parent]}"
    item[:children].each do |child|
      child_issue = Linear::Issues.create(team_key: TEAM, title: child, parent_id: issue["id"])
      info "  Created child #{child_issue["identifier"]} - #{child}"
    end
  end
end

bulk_create
