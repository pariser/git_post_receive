class PostcommitController < ApplicationController

  require 'jira4r/jira_tool.rb'
  require 'time'
  require 'yaml'
  require 'pp'

  def index

    # issue_key = 'MVPONE-1017'
    # jira = jira_connect
    # pp jira.getAvailableActions issue_key
    # pp jira.getComments issue_key
    # pp jira.getProjectByKey 'MVPONE'
    # pp jira.getIssue issue_key

    pp jira_projects

  end

  def new
    @payload = {
      :before => "5aef35982fb2d34e9d9d4502f6ede1072793222d",
      :repository => {
        :url => "http://github.com/defunkt/github",
        :name => "github",
        :description => "You're lookin' at it.",
        :watchers => 5,
        :forks => 2,
        :private => 1,
        :owner => {
          :email => "chris@ozmm.org",
          :name => "defunkt"
        }
      },
      :commits => [
        {
          :id => "41a212ee83ca127e3c8cf465891ab7216a705f59",
          :url => "http://github.com/defunkt/github/commit/41a212ee83ca127e3c8cf465891ab7216a705f59",
          :author => {
            :email => "chris@ozmm.org",
            :name => "Chris Wanstrath"
          },
          :message => "okay i give in",
          :timestamp => "2008-02-15T14:57:17-08:00",
          :added => ["filepath.rb"]
        },
        {
          :id => "de8251ff97ee194a289832576287d6f8ad74e3d0",
          :url => "http://github.com/defunkt/github/commit/de8251ff97ee194a289832576287d6f8ad74e3d0",
          :author => {
            :email => "chris@ozmm.org",
            :name => "Chris Wanstrath"
          },
          :message => "Fixes MVPONE-1017, comments on MVPONE-1018",
          :timestamp => "2008-02-15T14:36:34-08:00"
        }
      ],
      :after => "de8251ff97ee194a289832576287d6f8ad74e3d0",
      :ref => "refs/heads/master"
    }
  end

  def create
    @payload = ActiveSupport::JSON.decode params[:payload]
    @commented_issues = Set.new
    @resolved_issues = Set.new

    # Simple lookup for whether to resolve an issue
    project_keys = jira_projects.map {|p| p.key}
    r = Regexp.new('(fixe?[sd]?|resolve[sd]?)? (%s)-([0-9]+)' % [project_keys.join('|')], Regexp::IGNORECASE)

    @payload["commits"].each do |commit|

      begin
        time = Time.parse commit["timestamp"]
      rescue
        time = Time.now
      end

      rc = Jira4R::V2::RemoteComment.new
      rc.body = "Found related commit [%s] by %s (%s) at %s\n\n%s\n\n<Message auto-added by pariser's git post-receive hook magic>" \
      % [ commit["url"], commit["author"]["name"], commit["author"]["email"], time.to_s, commit["message"] ]

      commit["message"].scan(r) do |match|

        should_resolve_issue = !match[0].nil?
        issue_key = match[1] + "-" + match[2]

        # Comment on this issue
        begin
          jira.addComment(issue_key, rc)
        rescue
          Rails.logger.error("Failed to add comment to issue %s" % [issue_key])
        else
          Rails.logger.debug("Successfully added comment to issue %s" % [issue_key])
        end

        # Resolve this issue, as appropriate
        if should_resolve_issue
          begin
            available_actions = jira.getAvailableActions issue_key
            resolve_action = available_actions.find {|s| s.name == 'Resolve Issue'}
            if !resolve_action.nil?
              jira.progressWorkflowAction(issue_key, resolve_action.id.to_s, [])
            else
              Rails.logger.debug("Not allowed to resolve issue %s. Allowable actions: %s" % [issue_key, (available_actions.map {|s| s.name}).to_s])
            end
          rescue StandardError => e
            Rails.logger.error("Failed to resolve issue %s : %s" % [issue_key, e.to_s])
          else
            Rails.logger.debug("Successfully resolved issue %s" % [issue_key])
          end
        end

      end
    end
  end

  protected

  def jira
    # Connect to JIRA

    # Load configuration
    unless @jira_config
      @jira_config = YAML.load(File.new "config/jira.yml", 'r')
    end

    # Connect to JIRA
    unless @jira_connection
      @jira_connection = Jira4R::JiraTool.new(2, @jira_config['address'])
      @jira_connection.login(@jira_config['username'], @jira_config['password'])
    end

    # Return the connection
    @jira_connection
  end

  def jira_projects
    # Load the list of JIRA projects
    unless @jira_projects
      @jira_projects = jira.getProjectsNoSchemes()
    end

    @jira_projects
  end


end
