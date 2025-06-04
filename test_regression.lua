-- test_regression.lua
-- Quick script to test the regression issue

package.path = package.path .. ";./?.lua;./?/init.lua"

local TestRunner = require("test.TestRunner")

print("🐛 Testing the specific regression issue...")
print("=" .. string.rep("=", 50))

-- Run the specific test
TestRunner:runTest("Regression: Time Delta Issue (11min vs 5min)")
