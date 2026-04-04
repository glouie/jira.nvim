if exists("g:loaded_jira_nvim")
  finish
endif
let g:loaded_jira_nvim = 1

command! -nargs=? JiraOpenIssue   lua require("jira").open_issue(<q-args> ~= "" and <q-args> or nil)
command! -nargs=0 JiraOpenCursor  lua require("jira").open_issue_under_cursor()
command! -nargs=? JiraSearch      lua require("jira").open_jql_search(<q-args> ~= "" and { query = <q-args>, submit = true } or nil)
command! -nargs=0 JiraAssigned    lua require("jira").open_assigned_issues()
command! -nargs=0 JiraCreated     lua require("jira").open_created_issues()
command! -nargs=0 JiraRecent      lua require("jira").open_recent_issues()
command! -nargs=0 JiraHistory     lua require("jira").open_issue_history()
command! -nargs=? JiraFilter      lua require("jira").open_filter_search(<q-args> ~= "" and { default = <q-args>, submit = true } or nil)
command! -nargs=0 JiraFilters     lua require("jira").open_filter_list()
command! -nargs=0 JiraBuffer      lua require("jira").open_buffer_issue_list()
