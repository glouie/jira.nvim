-- test/helper.lua
-- Sets up the package path so require("jira.utils") etc. resolve from the repo root.
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
