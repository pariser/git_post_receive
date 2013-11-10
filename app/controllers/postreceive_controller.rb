class PostreceiveController < ApplicationController

  require 'jira4r/jira_tool.rb'
  require 'time'
  require 'yaml'
  require 'pp'

  # # Examples of what you may want to do with jira_tool
  # # and how you may do it inside this controller
  # # when we say issue_key, we mean "MVPONE-1017" or something similar
  # # when we say project_key, we mean "MVPONE" or something similar
  #
  # # Get details about the issue:
  # pp jira.getIssue issue_key
  #
  # # Get actions you can perform on that issue (i.e. resolve issue):
  # pp jira.getAvailableActions issue_key
  #
  # # Get comments about that issue:
  # pp jira.getComments issue_key
  #
  # # Get information about a given project:
  # pp jira.getProjectByKey project_key
  #
  # # the function jira_projects lets you know what projects are available
  # # in this JIRA instance:
  # pp jira_projects

  def new
    # The following is an example payload that github will actually post
    # on to a url attached to a post-receive hook

    @payload = {
      :pusher => {
        :name => "pariser",
        :email => "pariser@gmail.com"
      },
      :repository => {
        :name => "git_post_receive",
        :size => 236,
        :has_wiki => true,
        :created_at => "2012/01/06 09:37:50 -0800",
        :watchers => 1,
        :private => false,
        :url => "https://github.com/pariser/git_post_receive",
        :language => "Ruby",
        :fork => false,
        :pushed_at => "2012/01/06 18:14:25 -0800",
        :open_issues => 0,
        :has_downloads => true,
        :homepage => "",
        :has_issues => true,
        :forks => 1,
        :description => "Mucking around with post-commit hooks in Git, in part to integrate with JIRA",
        :owner => {
          :name => "pariser",
          :email => "pariser@gmail.com"
        }
      },
      :forced => false,
      :after => "9555a2b9d3e86dddec828c1ba9fb56c8510bc581",
      :deleted => false,
      :ref => "refs/heads/master",
      :commits =>
      [
       {
         :modified => [],
         :added => ["file"],
         :timestamp => "2012-01-06T18:13:56-08:00",
         :removed => [],
         :author => {
           :name => "Andrew Pariser",
           :username => "pariser",
           :email => "pariser@gmail.com"
         },
         :url => "https://github.com/pariser/git_post_receive/commit/9555a2b9d3e86dddec828c1ba9fb56c8510bc581",
         :id => "9555a2b9d3e86dddec828c1ba9fb56c8510bc581",
         :distinct => true,
         :message => "This commit fixes MVPONE-1017\n\nIt also starts work on MVPONE-1018"
       }
      ],
      :compare => "https://github.com/pariser/git_post_receive/compare/82ec878...9555a2b",
      :before => "82ec8783077c6b5827b4b8468b6ede00f14ec098",
      :created => false
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
      
      # Optional SSL parameters
      if @jira_config['ssl_version'] != nil
        @jira_connection.driver.streamhandler.client.ssl_config.ssl_version = @jira_config['ssl_version']
      end
      if @jira_config['ssl_verify'] == false
        @jira_connection.driver.options['protocol.http.ssl_config.verify_mode'] = OpenSSL::SSL::VERIFY_NONE
      end
      
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
