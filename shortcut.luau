--!nonstrict
-- shortcut.luau — плитка эквалайзера на главной Control Center.
-- Показывает активный профиль, гаснет когда эквалайзер в обходе,
-- по клику открывает панель с профилями.

local DIR = noctalia.pluginDir() or ""
local STATE = noctalia.expandPath("~/.local/state/equalizer/state.json")

local names = {}
local namesLoaded = false

local function loadNames()
  if namesLoaded then return end
  local raw = noctalia.readFile(DIR .. "/presets.json")
  if not raw then return end
  local ok, data = pcall(noctalia.json.decode, raw)
  if not ok or not data then return end
  for _, preset in ipairs(data.presets or {}) do
    names[preset.id] = preset.name
  end
  namesLoaded = true
end

local function readState()
  local raw = noctalia.readFile(STATE)
  if not raw then return {} end
  local ok, data = pcall(noctalia.json.decode, raw)
  if not ok or not data then return {} end
  return data
end

function update()
  loadNames()
  local st = readState()
  local preset = st.preset or "flat"
  local off = st.bypass == true

  shortcut.setIcon("adjustments-horizontal")
  shortcut.setLabel(names[preset] or "Эквалайзер")
  shortcut.setActive(not off)
  shortcut.setEnabled(true)
end

function onClick()
  noctalia.togglePanel("vlad-dev/equalizer:panel")
end

noctalia.setUpdateInterval(3000)
