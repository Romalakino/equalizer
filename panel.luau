--!nonstrict
-- panel.luau — эквалайзер: профили одним кликом.
--
-- Данные: presets.json рядом (имена, подсказки, полосы). Применение —
-- eqctl (EasyEffects), состояние читаем оттуда же, поэтому панель и движок
-- не расходятся. Кривая сверху — АЧХ выбранного профиля.

local DIR = noctalia.pluginDir() or ""
local STATE = noctalia.expandPath("~/.local/state/equalizer/state.json")

local data = nil          -- разобранный presets.json
local active = "flat"     -- id профиля
local bypass = false      -- эквалайзер в обходе
local running = false     -- EasyEffects запущен
local slots = {}          -- слот плитки -> id профиля

-- ── данные ──────────────────────────────────────────────────────

local function loadData()
  if data then return end
  local raw = noctalia.readFile(DIR .. "/presets.json")
  if raw then
    local ok, parsed = pcall(noctalia.json.decode, raw)
    if ok and parsed then data = parsed end
  end
  if not data then data = { bands = {}, presets = {} } end
end

local function presetById(id)
  for _, preset in ipairs(data.presets or {}) do
    if preset.id == id then return preset end
  end
  return nil
end

-- ── состояние ───────────────────────────────────────────────────

local function applyState(st)
  if type(st) ~= "table" then return end
  if st.preset then active = st.preset end
  bypass = st.bypass == true
  running = st.running == true
end

local function refresh()
  noctalia.runAsync({ DIR .. "/eqctl", "status" }, function(result)
    if not result or result.exitCode ~= 0 then return end
    local ok, st = pcall(noctalia.json.decode, result.stdout or "")
    if ok then applyState(st) end
    render()
  end)
end

-- ── кривая АЧХ ──────────────────────────────────────────────────

local RANGE = 10 -- дБ вверх/вниз, столько рисуем

local function curveValues()
  local preset = presetById(active)
  local gains = (preset and preset.gains) or {}
  local n = #gains
  if n == 0 then return { 0.5, 0.5 } end

  -- Сглаживание косинусом: между полосами линия идёт плавно, без изломов.
  local out = {}
  local steps = 56
  for i = 0, steps do
    local t = (i / steps) * (n - 1)
    local low = math.floor(t) + 1
    local high = math.min(low + 1, n)
    local f = t - math.floor(t)
    local a = gains[low] or 0
    local b = gains[high] or 0
    local g = a + (b - a) * (0.5 - 0.5 * math.cos(f * math.pi))
    out[#out + 1] = math.max(0, math.min(1, (g + RANGE) / (2 * RANGE)))
  end
  return out
end

-- ── вид ─────────────────────────────────────────────────────────

local function graphCard()
  local preset = presetById(active)
  local on = not bypass
  local color = on and "primary" or "on_surface/0.35"

  local head = {
    ui.label({ text = preset and preset.name or "—", fontSize = 13,
               fontWeight = "semibold", color = on and "on_surface" or "on_surface/0.55",
               flexGrow = 1 }),
    ui.label({ text = on and (preset and preset.hint or "") or "выключен",
               fontSize = 10, color = "on_surface/0.45", maxLines = 1 }),
  }

  local foot = {
    ui.label({ text = "32 Гц", fontSize = 9, color = "on_surface/0.35" }),
    ui.spacer({ flexGrow = 1 }),
    ui.label({ text = "1 кГц", fontSize = 9, color = "on_surface/0.35" }),
    ui.spacer({ flexGrow = 1 }),
    ui.label({ text = "16 кГц", fontSize = 9, color = "on_surface/0.35" }),
  }

  return ui.column({
    fill = "surface_variant/0.35", radius = 14,
    border = "on_surface/0.10", borderWidth = 1,
    paddingH = 14, paddingV = 12, gap = 6,
  }, {
    ui.row({ gap = 8, align = "center" }, head),
    ui.graph({
      values = curveValues(),
      height = 62,
      color = color,
      fillOpacity = on and 0.16 or 0.05,
      lineWidth = 2,
    }),
    ui.row({ gap = 0, align = "center" }, foot),
  })
end

local function tile(slot)
  local id = slots[slot]
  local preset = presetById(id)
  if not preset then return ui.box({ width = 0, height = 0 }) end

  local selected = (id == active)
  local dim = bypass and not selected

  local head = {
    ui.label({
      text = preset.name, fontSize = 12.5, fontWeight = "semibold",
      color = selected and "primary" or (dim and "on_surface/0.55" or "on_surface"),
      maxLines = 1, flexGrow = 1,
    }),
  }
  if selected then
    head[#head + 1] = ui.glyph({ name = "check", size = 12, color = "primary" })
  end

  return ui.column({
    gap = 3, flexGrow = 1, minHeight = 54,
    fill = selected and "primary/0.14" or "surface_variant/0.40",
    border = selected and "primary/0.45" or "on_surface/0.08",
    borderWidth = 1, radius = 12,
    paddingH = 12, paddingV = 9,
    onClick = "onPick" .. slot,
  }, {
    ui.row({ gap = 6, align = "center" }, head),
    ui.label({
      text = preset.hint or "", fontSize = 9.5,
      color = "on_surface/0.45", maxLines = 1,
    }),
  })
end

local function grid()
  local rows = {}
  local count = #(data.presets or {})
  local index = 1
  for row = 1, math.ceil(count / 2) do
    local cells = {}
    for col = 1, 2 do
      if index <= count then
        slots[index] = data.presets[index].id
        cells[#cells + 1] = tile(index)
        index = index + 1
      else
        cells[#cells + 1] = ui.box({ flexGrow = 1 })
      end
    end
    rows[#rows + 1] = ui.row({ gap = 8, flexGrow = 1 }, cells)
  end
  return ui.column({ gap = 8, flexGrow = 1 }, rows)
end

render = function()
  loadData()

  local header = ui.row({ gap = 10, align = "center", paddingH = 16, paddingV = 14 }, {
    ui.glyph({ name = "adjustments-horizontal", size = 18, color = bypass and "on_surface/0.45" or "primary" }),
    ui.label({ text = noctalia.tr("panel.title"), fontSize = 16, fontWeight = "semibold", flexGrow = 1 }),
    ui.toggle({ checked = not bypass, onChange = "onEnabled" }),
    ui.button({ glyph = "x", glyphSize = 15, variant = "ghost", onClick = "onClosePanel" }),
  })

  local body = ui.column({ gap = 12, paddingH = 16, paddingV = 14, flexGrow = 1 }, {
    graphCard(),
    grid(),
  })

  panel.render(ui.column({ gap = 0, flexGrow = 1 }, { header, ui.separator({}), body }))
end

-- ── действия ────────────────────────────────────────────────────

local function run(args)
  noctalia.runAsync(args, function(result)
    if not result or result.exitCode ~= 0 then
      noctalia.notifyError(noctalia.tr("panel.title"), noctalia.tr("error.apply"))
      return
    end
    refresh()
  end)
end

local function pick(slot)
  local id = slots[slot]
  if not id then return end
  active = id
  bypass = false
  render()
  run({ DIR .. "/eqctl", "apply", id })
end

function onPick1() pick(1) end
function onPick2() pick(2) end
function onPick3() pick(3) end
function onPick4() pick(4) end
function onPick5() pick(5) end
function onPick6() pick(6) end

function onEnabled(value)
  local checked = (value == "true")
  bypass = not checked
  render()
  run({ DIR .. "/eqctl", "bypass", checked and "off" or "on" })
end

function onClosePanel() panel.close() end

-- ── жизненный цикл ──────────────────────────────────────────────

function onOpen()
  loadData()
  render()
  refresh()
end

function onClose() end
