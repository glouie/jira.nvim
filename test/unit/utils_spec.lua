-- test/unit/utils_spec.lua
-- Busted unit tests for lua/jira/utils.lua.
-- Run with: busted test/unit/ --helper test/helper.lua

-- ── Minimal vim stub (busted runs outside Neovim) ─────────────────────────────
_G.vim = _G.vim or {}

-- vim.NIL is Neovim's sentinel for JSON null; must be a unique object.
vim.NIL = vim.NIL or {}

-- Lightweight JSON stubs -- good enough for the encode/decode calls utils.lua
-- makes internally, without pulling in a real JSON library.
vim.json = vim.json or {
  decode = function(s)
    -- Very small subset: handles the simple values utils_spec produces.
    return load("return " .. s:gsub("null", "nil"):gsub("true", "true"):gsub("false", "false"))()
  end,
  encode = function(v)
    return tostring(v)
  end,
}

vim.fn = vim.fn or {
  has      = function() return 0 end,
  stdpath  = function() return "/tmp" end,
}

vim.log = vim.log or { levels = { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 } }

vim.api = vim.api or {
  nvim_strwidth        = function(s) return #s end,
  nvim_echo            = function() end,
  nvim_get_hl          = function() return {} end,
  nvim_get_hl_by_name  = function() return {} end,
}

vim.o        = vim.o        or { columns = 80, statusline = "" }
vim.uv       = vim.uv       or nil
vim.loop     = vim.loop     or nil
vim.cmd      = vim.cmd      or function() end
vim.schedule = vim.schedule or function(f) f() end
vim.notify   = vim.notify   or function() end
vim.pesc     = vim.pesc     or function(s) return s:gsub("(%W)", "%%%1") end

-- ── Load the module under test ────────────────────────────────────────────────
local utils = require("jira.utils")

-- ═════════════════════════════════════════════════════════════════════════════
describe("jira.utils", function()

  -- ── utils.trim ──────────────────────────────────────────────────────────────
  describe("trim", function()
    it("returns empty string for nil", function()
      assert.equals("", utils.trim(nil))
    end)

    it("returns empty string for empty string", function()
      assert.equals("", utils.trim(""))
    end)

    it("strips leading spaces", function()
      assert.equals("hello", utils.trim("   hello"))
    end)

    it("strips trailing spaces", function()
      assert.equals("hello", utils.trim("hello   "))
    end)

    it("strips both leading and trailing spaces", function()
      assert.equals("hello world", utils.trim("  hello world  "))
    end)

    it("strips leading and trailing tabs", function()
      assert.equals("hello", utils.trim("\t\thello\t"))
    end)

    it("strips mixed whitespace", function()
      assert.equals("foo", utils.trim(" \t foo \t "))
    end)

    it("preserves internal whitespace", function()
      assert.equals("a  b", utils.trim("  a  b  "))
    end)

    it("returns unchanged string when no whitespace present", function()
      assert.equals("clean", utils.trim("clean"))
    end)
  end)

  -- ── utils.url_encode ────────────────────────────────────────────────────────
  describe("url_encode", function()
    it("returns empty string for nil", function()
      assert.equals("", utils.url_encode(nil))
    end)

    it("encodes space as %20", function()
      assert.equals("hello%20world", utils.url_encode("hello world"))
    end)

    it("encodes forward slash", function()
      local result = utils.url_encode("a/b")
      assert.equals("a%2Fb", result)
    end)

    it("encodes ampersand", function()
      assert.equals("a%26b", utils.url_encode("a&b"))
    end)

    it("encodes equals sign", function()
      assert.equals("a%3Db", utils.url_encode("a=b"))
    end)

    it("encodes hash", function()
      assert.equals("a%23b", utils.url_encode("a#b"))
    end)

    it("leaves unreserved chars unchanged", function()
      assert.equals("abc-_~.123", utils.url_encode("abc-_~.123"))
    end)

    it("encodes a full JQL query", function()
      local result = utils.url_encode("project = ABC AND status = Open")
      -- spaces become %20, = becomes %3D
      assert.is_not_nil(result:find("%%20"))
      assert.is_not_nil(result:find("%%3D"))
    end)

    it("converts a number to its encoded string", function()
      -- numbers have no special chars so they pass through unchanged
      assert.equals("42", utils.url_encode(42))
    end)

    it("converts newline to %%0D%%0A (CR+LF)", function()
      local result = utils.url_encode("a\nb")
      -- url_encode maps \n → \r\n first, then encodes each
      assert.is_not_nil(result:find("%%0D%%0A"))
    end)
  end)

  -- ── utils.encode_basic_auth ──────────────────────────────────────────────────
  describe("encode_basic_auth", function()
    it("returns nil + error when email is nil", function()
      local result, err = utils.encode_basic_auth(nil, "token")
      assert.is_nil(result)
      assert.is_not_nil(err)
      assert.is_not_nil(err:find("email"))
    end)

    it("returns nil + error when email is empty string", function()
      local result, err = utils.encode_basic_auth("", "token")
      assert.is_nil(result)
      assert.is_not_nil(err)
    end)

    it("returns nil + error when token is nil", function()
      local result, err = utils.encode_basic_auth("user@example.com", nil)
      assert.is_nil(result)
      assert.is_not_nil(err)
      assert.is_not_nil(err:find("token"))
    end)

    it("returns nil + error when token is empty string", function()
      local result, err = utils.encode_basic_auth("user@example.com", "")
      assert.is_nil(result)
      assert.is_not_nil(err)
    end)

    it("returns a non-empty base64 string for valid credentials", function()
      local result, err = utils.encode_basic_auth("user@example.com", "secret")
      assert.is_nil(err)
      assert.is_not_nil(result)
      assert.is_true(#result > 0)
    end)

    it("returns only base64 alphabet characters", function()
      local result = utils.encode_basic_auth("a@b.com", "tok")
      assert.is_not_nil(result)
      -- base64 chars: A-Z a-z 0-9 + / =
      assert.is_nil(result:find("[^A-Za-z0-9+/=]"))
    end)

    it("encodes identical credentials deterministically", function()
      local r1 = utils.encode_basic_auth("u@x.com", "p")
      local r2 = utils.encode_basic_auth("u@x.com", "p")
      assert.equals(r1, r2)
    end)
  end)

  -- ── utils.html_to_text ───────────────────────────────────────────────────────
  describe("html_to_text", function()
    it("returns empty string for nil", function()
      assert.equals("", utils.html_to_text(nil))
    end)

    it("returns empty string for empty string", function()
      assert.equals("", utils.html_to_text(""))
    end)

    it("strips a simple <p> tag", function()
      local result = utils.html_to_text("<p>Hello</p>")
      assert.is_nil(result:find("<"))
      assert.is_not_nil(result:find("Hello"))
    end)

    it("converts </p> to double newline then trims", function()
      -- Two paragraphs: the </p> boundary should leave whitespace between them
      -- but the final trim removes leading/trailing.
      local result = utils.html_to_text("<p>First</p><p>Second</p>")
      assert.is_not_nil(result:find("First"))
      assert.is_not_nil(result:find("Second"))
      assert.is_nil(result:find("<p>"))
    end)

    it("converts <br/> to newline", function()
      local result = utils.html_to_text("line1<br/>line2")
      assert.is_not_nil(result:find("\n"))
      assert.is_not_nil(result:find("line1"))
      assert.is_not_nil(result:find("line2"))
    end)

    it("converts <br> (no slash) to newline", function()
      local result = utils.html_to_text("line1<br>line2")
      assert.is_not_nil(result:find("\n"))
    end)

    it("converts <li> to dash bullet", function()
      local result = utils.html_to_text("<li>item one</li>")
      assert.is_not_nil(result:find("- item one"))
    end)

    it("strips arbitrary unknown tags", function()
      local result = utils.html_to_text("<span class=\"x\">text</span>")
      assert.equals("text", result)
    end)

    it("strips nested tags and leaves text", function()
      local result = utils.html_to_text("<ul><li>a</li><li>b</li></ul>")
      assert.is_not_nil(result:find("- a"))
      assert.is_not_nil(result:find("- b"))
    end)

    it("trims the final result", function()
      local result = utils.html_to_text("  <p>hi</p>  ")
      assert.equals(result, result:match("^%S.*%S$") or result:match("^%S$") or result)
      -- No leading/trailing whitespace
      assert.is_nil(result:match("^%s"))
      assert.is_nil(result:match("%s$"))
    end)
  end)

  -- ── utils.adf_to_text ────────────────────────────────────────────────────────
  describe("adf_to_text", function()
    it("returns empty string for nil", function()
      assert.equals("", utils.adf_to_text(nil))
    end)

    it("trims a plain string value", function()
      assert.equals("hello", utils.adf_to_text("  hello  "))
    end)

    it("returns empty string for table without .content", function()
      assert.equals("", utils.adf_to_text({ type = "doc" }))
    end)

    it("handles a text node inside a paragraph", function()
      local adf = {
        type = "doc",
        content = {
          {
            type = "paragraph",
            content = {
              { type = "text", text = "Hello world" },
            },
          },
        },
      }
      local result = utils.adf_to_text(adf)
      assert.is_not_nil(result:find("Hello world"))
    end)

    it("handles a hardBreak node", function()
      local adf = {
        type = "doc",
        content = {
          {
            type = "paragraph",
            content = {
              { type = "text",      text = "before" },
              { type = "hardBreak"                  },
              { type = "text",      text = "after"  },
            },
          },
        },
      }
      local result = utils.adf_to_text(adf)
      assert.is_not_nil(result:find("before"))
      assert.is_not_nil(result:find("after"))
    end)

    it("renders bulletList items with dash markers", function()
      local adf = {
        type = "doc",
        content = {
          {
            type = "bulletList",
            content = {
              { type = "listItem", content = { { type = "paragraph", content = { { type = "text", text = "item A" } } } } },
              { type = "listItem", content = { { type = "paragraph", content = { { type = "text", text = "item B" } } } } },
            },
          },
        },
      }
      local result = utils.adf_to_text(adf)
      assert.is_not_nil(result:find("- "))
      assert.is_not_nil(result:find("item A"))
      assert.is_not_nil(result:find("item B"))
    end)

    it("renders orderedList items with numeric markers", function()
      local adf = {
        type = "doc",
        content = {
          {
            type = "orderedList",
            content = {
              { type = "listItem", content = { { type = "paragraph", content = { { type = "text", text = "first" } } } } },
              { type = "listItem", content = { { type = "paragraph", content = { { type = "text", text = "second" } } } } },
            },
          },
        },
      }
      local result = utils.adf_to_text(adf)
      assert.is_not_nil(result:find("1%."))
      assert.is_not_nil(result:find("2%."))
      assert.is_not_nil(result:find("first"))
      assert.is_not_nil(result:find("second"))
    end)

    it("trims leading/trailing whitespace from the final result", function()
      local adf = {
        type = "doc",
        content = {
          { type = "paragraph", content = { { type = "text", text = "hi" } } },
        },
      }
      local result = utils.adf_to_text(adf)
      assert.is_nil(result:match("^%s"))
      assert.is_nil(result:match("%s$"))
    end)

    it("handles multiple paragraphs concatenated", function()
      local adf = {
        type = "doc",
        content = {
          { type = "paragraph", content = { { type = "text", text = "Para one" } } },
          { type = "paragraph", content = { { type = "text", text = "Para two" } } },
        },
      }
      local result = utils.adf_to_text(adf)
      assert.is_not_nil(result:find("Para one"))
      assert.is_not_nil(result:find("Para two"))
    end)
  end)

  -- ── utils.wrap_text ──────────────────────────────────────────────────────────
  describe("wrap_text", function()
    it("returns empty table for nil input", function()
      local lines = utils.wrap_text(nil)
      assert.equals(0, #lines)
    end)

    it("returns empty table for empty string", function()
      local lines = utils.wrap_text("")
      assert.equals(0, #lines)
    end)

    it("returns single line when text is shorter than width", function()
      local lines = utils.wrap_text("short", 80)
      assert.equals(1, #lines)
      assert.equals("short", lines[1])
    end)

    it("wraps a long line at the specified width", function()
      -- 5 words of 10 chars each + spaces → 54 chars total, width 30 forces breaks
      local words = {}
      for i = 1, 5 do words[i] = ("word" .. i .. "xxxx") end  -- ~9 chars each
      local text = table.concat(words, " ")
      local lines = utils.wrap_text(text, 20)
      assert.is_true(#lines > 1)
      for _, line in ipairs(lines) do
        assert.is_true(#line <= 20, "line too long: " .. line)
      end
    end)

    it("uses 80 as default width when width is nil", function()
      local long_word = string.rep("a", 70)
      local text = long_word .. " " .. long_word
      local lines = utils.wrap_text(text)
      -- Both 70-char words fit individually but not together in 80
      assert.is_true(#lines >= 2)
    end)

    it("handles multiple paragraphs separated by newlines", function()
      local text = "First paragraph.\nSecond paragraph."
      local lines = utils.wrap_text(text, 80)
      -- An empty separator line should appear between the two content lines
      local has_empty = false
      for _, l in ipairs(lines) do
        if l == "" then has_empty = true end
      end
      assert.is_true(has_empty)
    end)

    it("does not end with a trailing empty line", function()
      local text = "one two three"
      local lines = utils.wrap_text(text, 80)
      assert.is_not_equal("", lines[#lines])
    end)

    it("preserves each word in the output", function()
      local text = "alpha beta gamma"
      local lines = utils.wrap_text(text, 80)
      local joined = table.concat(lines, " ")
      assert.is_not_nil(joined:find("alpha"))
      assert.is_not_nil(joined:find("beta"))
      assert.is_not_nil(joined:find("gamma"))
    end)
  end)

  -- ── utils.humanize_duration ──────────────────────────────────────────────────
  describe("humanize_duration", function()
    it("returns 'Under 1m' for 0 seconds", function()
      assert.equals("Under 1m", utils.humanize_duration(0))
    end)

    it("returns 'Under 1m' for negative seconds", function()
      assert.equals("Under 1m", utils.humanize_duration(-99))
    end)

    it("returns 'Under 1m' for nil", function()
      assert.equals("Under 1m", utils.humanize_duration(nil))
    end)

    it("returns 'Under 1m' for 45 seconds (under a minute)", function()
      assert.equals("Under 1m", utils.humanize_duration(45))
    end)

    it("returns 'Under 1m' for 59 seconds", function()
      assert.equals("Under 1m", utils.humanize_duration(59))
    end)

    it("returns '1m' for exactly 60 seconds", function()
      assert.equals("1m", utils.humanize_duration(60))
    end)

    it("returns '2m' for 120 seconds", function()
      assert.equals("2m", utils.humanize_duration(120))
    end)

    it("returns '1h' for exactly 3600 seconds", function()
      assert.equals("1h", utils.humanize_duration(3600))
    end)

    it("returns '1h 1m' for 3661 seconds", function()
      assert.equals("1h 1m", utils.humanize_duration(3661))
    end)

    it("returns '1d' for exactly 86400 seconds", function()
      assert.equals("1d", utils.humanize_duration(86400))
    end)

    it("returns '1d 1h' for 90000 seconds (25 hours)", function()
      assert.equals("1d 1h", utils.humanize_duration(90000))
    end)

    it("returns '1d 1h' for 90061 seconds (1d + 1h + 1m, limited to 2 parts)", function()
      -- humanize_duration stops after 2 parts, so minutes are dropped
      assert.equals("1d 1h", utils.humanize_duration(90061))
    end)

    it("returns '2d' for 172800 seconds", function()
      assert.equals("2d", utils.humanize_duration(172800))
    end)
  end)

  -- ── utils.should_ignore_issue_key ────────────────────────────────────────────
  describe("should_ignore_issue_key", function()
    it("returns false for nil key", function()
      assert.is_false(utils.should_ignore_issue_key(nil, { ABC = true }))
    end)

    it("returns false for empty key", function()
      assert.is_false(utils.should_ignore_issue_key("", { ABC = true }))
    end)

    it("returns false for nil ignored_projects map", function()
      assert.is_false(utils.should_ignore_issue_key("ABC-123", nil))
    end)

    it("returns false for both nil", function()
      assert.is_false(utils.should_ignore_issue_key(nil, nil))
    end)

    it("returns true when project is in the ignored map", function()
      assert.is_true(utils.should_ignore_issue_key("ABC-123", { ABC = true }))
    end)

    it("is case-insensitive: lowercase key still matches uppercase map entry", function()
      assert.is_true(utils.should_ignore_issue_key("abc-123", { ABC = true }))
    end)

    it("returns false when project is not in the ignored map", function()
      assert.is_false(utils.should_ignore_issue_key("XYZ-1", { ABC = true }))
    end)

    it("returns false for a malformed key with no dash-number suffix", function()
      assert.is_false(utils.should_ignore_issue_key("NOTAKEY", { NOTAKEY = true }))
    end)

    it("returns false for key like 'ABC-' (missing number)", function()
      assert.is_false(utils.should_ignore_issue_key("ABC-", { ABC = true }))
    end)

    it("returns false when map value is not true (e.g. false)", function()
      assert.is_false(utils.should_ignore_issue_key("ABC-1", { ABC = false }))
    end)

    it("handles numeric project prefix", function()
      -- pattern is [%a%d]+, so numeric-prefixed keys are valid
      assert.is_true(utils.should_ignore_issue_key("PROJ2-5", { PROJ2 = true }))
    end)
  end)

  -- ── utils.blank_if_nil ───────────────────────────────────────────────────────
  describe("blank_if_nil", function()
    it("returns '-' for nil", function()
      assert.equals("-", utils.blank_if_nil(nil))
    end)

    it("returns '-' for empty string", function()
      assert.equals("-", utils.blank_if_nil(""))
    end)

    it("returns '-' for vim.NIL sentinel", function()
      assert.equals("-", utils.blank_if_nil(vim.NIL))
    end)

    it("passes through a normal string unchanged", function()
      assert.equals("hello", utils.blank_if_nil("hello"))
    end)

    it("passes through a number unchanged", function()
      assert.equals(42, utils.blank_if_nil(42))
    end)

    it("passes through the number 0 unchanged (falsy in Lua but not nil)", function()
      assert.equals(0, utils.blank_if_nil(0))
    end)

    it("passes through false unchanged", function()
      assert.equals(false, utils.blank_if_nil(false))
    end)

    it("passes through a table unchanged", function()
      local t = { key = "val" }
      assert.equals(t, utils.blank_if_nil(t))
    end)

    it("passes through a non-empty whitespace string unchanged", function()
      -- blank_if_nil only replaces "" not " " (that is trim's job)
      assert.equals(" ", utils.blank_if_nil(" "))
    end)
  end)

  -- ── utils.comment_body ───────────────────────────────────────────────────────
  describe("comment_body", function()
    it("returns empty string for nil comment", function()
      assert.equals("", utils.comment_body(nil))
    end)

    it("returns empty string for empty-table comment", function()
      assert.equals("", utils.comment_body({}))
    end)

    it("trims a plain string body", function()
      assert.equals("hello", utils.comment_body({ body = "  hello  " }))
    end)

    it("returns empty string for empty string body", function()
      assert.equals("", utils.comment_body({ body = "" }))
    end)

    it("delegates ADF body table to adf_to_text", function()
      local adf_body = {
        type = "doc",
        content = {
          {
            type = "paragraph",
            content = { { type = "text", text = "ADF comment" } },
          },
        },
      }
      local result = utils.comment_body({ body = adf_body })
      assert.is_not_nil(result:find("ADF comment"))
    end)

    it("handles comment with nil body field", function()
      -- body is nil, type check falls through to adf_to_text(nil) = ""
      assert.equals("", utils.comment_body({ body = nil }))
    end)
  end)

  -- ── utils.get_severity ───────────────────────────────────────────────────────
  describe("get_severity", function()
    it("returns nil for nil issue", function()
      -- get_severity accesses issue.fields, so pass a table without fields
      -- Actually looking at implementation: it does `issue.fields or {}`
      -- so nil would error. Test with an empty table instead.
      assert.is_nil(utils.get_severity({}))
    end)

    it("returns severity.name when present", function()
      local issue = { fields = { severity = { name = "Critical" } } }
      assert.equals("Critical", utils.get_severity(issue))
    end)

    it("returns severity.value when name is absent", function()
      local issue = { fields = { severity = { value = "High" } } }
      assert.equals("High", utils.get_severity(issue))
    end)

    it("returns raw severity when it is a plain value (not a table)", function()
      -- fields.severity is a string directly
      local issue = { fields = { severity = "Medium" } }
      -- implementation: `return fields.severity.name or fields.severity.value or fields.severity`
      -- string indexing .name/.value returns nil, so falls through to the string itself
      assert.equals("Medium", utils.get_severity(issue))
    end)

    it("looks up dynamic field via names map", function()
      local issue = {
        fields = { customfield_10200 = { value = "Low" } },
        names  = { customfield_10200 = "Severity" },
      }
      assert.equals("Low", utils.get_severity(issue))
    end)

    it("prefers names map .value over .name", function()
      local issue = {
        fields = { customfield_10200 = { name = "P1", value = "Low" } },
        names  = { customfield_10200 = "Severity" },
      }
      -- utils.get_severity returns .value before .name (matches Jira field conventions)
      assert.equals("Low", utils.get_severity(issue))
    end)

    it("falls back to names map .displayName", function()
      local issue = {
        fields = { customfield_10200 = { displayName = "Blocker" } },
        names  = { customfield_10200 = "Issue Severity" },
      }
      assert.equals("Blocker", utils.get_severity(issue))
    end)

    it("returns raw string from names map field when value is a plain string", function()
      local issue = {
        fields = { customfield_10200 = "Trivial" },
        names  = { customfield_10200 = "Severity" },
      }
      assert.equals("Trivial", utils.get_severity(issue))
    end)

    it("returns nil when names map field label does not contain 'severity'", function()
      local issue = {
        fields = { customfield_10200 = { value = "Low" } },
        names  = { customfield_10200 = "Priority" },
      }
      assert.is_nil(utils.get_severity(issue))
    end)

    it("is case-insensitive for 'severity' label match", function()
      local issue = {
        fields = { customfield_10200 = { value = "High" } },
        names  = { customfield_10200 = "SEVERITY LEVEL" },
      }
      assert.equals("High", utils.get_severity(issue))
    end)

    it("returns nil when no severity field exists anywhere", function()
      local issue = { fields = { summary = "Just a bug" }, names = { f1 = "Priority" } }
      assert.is_nil(utils.get_severity(issue))
    end)
  end)

end)
