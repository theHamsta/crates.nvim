---@class Version
---@field num string
---@field features Features
---@field yanked boolean
---@field parsed SemVer
---@field created DateTime

---@class Features
---@field get_feat fun(self: Features, name:string): Feature|nil, integer

---@class Feature
---@field name string
---@field members string[]

local M = {}

M.Features = {}
local Features = M.Features

function Features.new(obj)
    return setmetatable(obj, { __index = Features })
end

---@param self Features
---@param name string
---@return Feature|nil, integer
function Features:get_feat(name)
    for i,f in ipairs(self) do
        if f.name == name then
            return f, i
        end
    end

    return nil
end

local job = require('plenary.job')
local semver = require('crates.semver')
local DateTime = require('crates.time').DateTime

local endpoint = "https://crates.io/api/v1"
local useragent = vim.fn.shellescape("crates.nvim (https://github.com/saecki/crates.nvim)")

local running_jobs = {}

---@param name string
---@param callback function(versions Version[])
function M.fetch_crate_versions(name, callback)
    if running_jobs[name] then
        return
    end

    local url = string.format("%s/crates/%s/versions", endpoint, name)
    local resp = nil

    local function parse_json()
        if not resp then
            callback(nil)
            return
        end

        local success, data = pcall(vim.fn.json_decode, resp)
        if not success then
            data = nil
        end

        local versions = {}
        if data and type(data) == "table" and data.versions then
            for _,v in ipairs(data.versions) do
                if v.num then
                    local version = {
                        num = v.num,
                        features = Features.new {},
                        yanked = v.yanked,
                        parsed = semver.parse_version(v.num),
                        created = DateTime.parse_rfc_3339(v.created_at)
                    }

                    for n,m in pairs(v.features) do
                        table.sort(m)
                        table.insert(version.features, {
                            name = n,
                            members = m,
                        })
                    end

                    -- add optional dependency members as features
                    for _,f in ipairs(version.features) do
                        for _,m in ipairs(f.members) do
                            if not version.features[m] then
                                version.features[m] = {
                                    name = m,
                                    members = {},
                                }
                            end
                        end
                    end

                    -- sort features alphabetically
                    table.sort(version.features, function (a, b)
                        return a.name < b.name
                    end)

                    table.insert(versions, version)
                end
            end
        end

        callback(versions)
    end

    local function on_exit(j, code, _)
        if code == 0 then
            resp = table.concat(j:result(), "\n")
        end

        vim.schedule(parse_json)

        running_jobs[name] = nil
    end

    local j = job:new {
        command = "curl",
        args = { "-sLA", useragent, url },
        on_exit = vim.schedule_wrap(on_exit),
    }

    running_jobs[name] = j

    j:start()
end

return M
