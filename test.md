# jira.nvim Coloration Test Matrix

The following synthetic Jira issues exercise every highlight used in the popup. Use them (or clone their field combinations) when seeding fixtures or mocking API responses.

## Issue Catalog

| Issue Key | Summary                    | Priority     | Severity | Special Fields                                                          | Expected Coverage                                                  |
| --------- | -------------------------- | ------------ | -------- | ----------------------------------------------------------------------- | ------------------------------------------------------------------ |
| SPL-101   | Login fails for admin role | P0 / Blocker | SEV-0    | URL present, comments and changes, Fix Versions: 1.0.0                  | Summary divider, Description, Comment/Change headers, URL bar link |
| SPL-102   | Payment retries spike      | P1 / High    | SEV-1    | Assigned + Reporter active, Resolution empty                            | Details pane priority/severity slots, active user highlights       |
| SPL-103   | Settings toggle missing    | P2 / Medium  | SEV-2    | Still Open status, open duration highlight, due date populated          | Open duration indicator, timestamp colors                          |
| SPL-104   | Mobile tooltip typo        | P3 / Low     | SEV-3    | Reporter inactive, Assignee inactive, Assignee history includes 3 users | Inactive user style + assignee history palette                     |
| SPL-105   | API schema drift           | Highest      | Critical | Multiple fix/affects versions, status Done, resolution set              | Version + statusline colors                                        |
| SPL-106   | OAuth redirect mismatch    | High         | Major    | Rich description markdown + attachment links                            | Markdown syntax highlighting + link tint                           |

## Test Flow

1. Load each issue through `:lua require("jira").open_issue("<ISSUE>")` using mocked API data or fixtures.
2. Verify the _summary title_, underline, and the new divider line render before the Description header.
3. Confirm the _Details_ pane background spans the entire sidebar, regardless of line length.
4. Check that the _URL/shortcut_ bar inherits the same background color, with both the URL row and navigation legend aligned.
5. Ensure margin spacing keeps the content inset from the popup border while the shortcut bar now rests directly on the window edge.
6. Review color-specific cases per issue:
   - SPL-101: timestamp, comment, and change highlights.
   - SPL-102 / SPL-105: priority & severity shades plus resolution row.
   - SPL-103: `Still Open` indicator in amber and due-date timestamp formatting.
   - SPL-104: inactive users appear muted; rotating assignees reuse unique colors.
   - SPL-106: markdown + hyperlinks use dedicated highlight groups.

## Notes

- Populate comments and history entries so that both sections are rendered; otherwise summary/footer separators will still appear but the highlights above may be skipped.
- When validating colors, check both focused and unfocused panes to ensure the `NormalNC` override keeps the detail and shortcut backgrounds consistent.

SPL-283281 - test that the range of numbers are high enough
https://www.google.com

project = SPL and issuetype = Bug and assignee in (currentUser())
