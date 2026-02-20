local M = {}

local function deep_copy(value)
  if type(value) ~= "table" then
    return value
  end

  local out = {}
  for k, v in pairs(value) do
    out[k] = deep_copy(v)
  end
  return out
end

local function deep_merge(base, override)
  local out = deep_copy(base)
  for k, v in pairs(override or {}) do
    local base_value = out[k]
    local both_tables = type(v) == "table" and type(base_value) == "table"
    local has_string_keys = false

    if both_tables then
      for key, _ in pairs(v) do
        if type(key) ~= "number" then
          has_string_keys = true
          break
        end
      end
      if has_string_keys then
        for key, _ in pairs(base_value) do
          if type(key) ~= "number" then
            has_string_keys = true
            break
          end
        end
      end
    end

    if both_tables and has_string_keys then
      out[k] = deep_merge(out[k], v)
    else
      out[k] = deep_copy(v)
    end
  end
  return out
end

local function normalize_hostname(hostname)
  local lowered = string.lower(hostname or "")
  return (lowered:gsub("[^a-z0-9]", "_"))
end

local function maybe_require(module_name)
  local ok, mod = pcall(require, module_name)
  if ok and type(mod) == "table" then
    return mod
  end
  return {}
end

function M.load()
  local defaults = maybe_require("config.defaults")
  local common = maybe_require("config.overrides.common")

  local hostname = normalize_hostname(hs.host.localizedName())
  local host_overrides = maybe_require("config.overrides.hosts." .. hostname)
  local local_overrides = maybe_require("config.local")

  return deep_merge(
    deep_merge(
      deep_merge(defaults, common),
      host_overrides
    ),
    local_overrides
  )
end

return M
