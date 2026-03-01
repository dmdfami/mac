#!/usr/bin/env node
const { execSync } = require("child_process");
const path = require("path");
execSync(`bash ${path.join(__dirname, "..", "setup.sh")}`, { stdio: "inherit" });
