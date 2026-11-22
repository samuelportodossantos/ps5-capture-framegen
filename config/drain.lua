-- Esvazia a fila da placa de captura quando o atraso cresce.
--
-- Com o lsfg-vk em V-Sync (FIFO), cada quadro do mpv vira N quadros na tela e a apresentação BLOQUEIA:
-- em x4 a 120 Hz o mpv consome exatamente 30 quadros/s. Qualquer fila que se forme (o mpv leva ~1 s
-- para iniciar o Vulkan enquanto a placa já captura; janela escondida; engasgo do driver) fica presa
-- para sempre, porque entra o mesmo tanto que sai (medido: ~0,7 s de atraso desde a partida).
--
-- O horário de cada quadro (time-pos) é o relógio monotônico do kernel na hora da captura. O script
-- alinha o relógio do mpv a ele uma vez e mede o atraso real (agora - captura do quadro na tela).
-- Usa o MENOR atraso da última janela (~0,5 s): um quadro parado na tela fica "velho" sem haver fila,
-- mas com fila até o menor valor fica alto. Acima de LIMITE, descarta 3 de cada 4 quadros (lê 4x mais
-- rápido do que mostra) até o menor atraso voltar abaixo de VOLTA.

local utils = require "mp.utils"

local LIMITE = 0.08   -- s: menor atraso da janela acima disso = há fila (normal medido: ~33 ms)
local VOLTA  = 0.05   -- s: menor atraso abaixo disso = fila vazia
local JANELA = 16     -- amostras (x 0,033 s ~ 0,5 s)
local DRENO  = { { name = "lavfi", params = { graph = "framestep=4" } } }

-- relógio monotônico do kernel (CLOCK_MONOTONIC), o mesmo dos horários de captura da placa
local function monotonic()
  local r = utils.subprocess({ args = { "python3", "-I", "-c", "import time; print(time.monotonic())" },
                               cancellable = false, playback_only = false })
  return r and r.status == 0 and tonumber(r.stdout) or nil
end

local t0 = mp.get_time(); local mono = monotonic(); local t1 = mp.get_time()
local offset = mono and (mono - (t0 + t1) / 2) or nil
if not offset then mp.msg.warn("sem python3: usando atraso relativo ao melhor já visto") end

local min_visto, amostras, esvaziando, filtro_normal = nil, {}, false, nil

-- Começa já esvaziando: enquanto o mpv inicia, a placa enche a fila (medido: ~0,9 s na partida).
filtro_normal = mp.get_property_native("vf")
mp.set_property_native("vf", DRENO)
esvaziando = true

local function atraso(tp)
  if offset then return mp.get_time() + offset - tp end
  local off = mp.get_time() - tp                      -- plano B: relativo ao menor já visto
  if not min_visto or off < min_visto then min_visto = off end
  return off - min_visto + 0.033
end

mp.add_periodic_timer(1 / 30, function()
  local tp = mp.get_property_number("time-pos")
  if not tp then return end
  local a = atraso(tp)
  if a > 10 or a < -1 then return end                 -- antes do primeiro quadro válido
  amostras[#amostras + 1] = a
  if #amostras > JANELA then table.remove(amostras, 1) end
  if #amostras < JANELA then return end
  local m = math.min(table.unpack and table.unpack(amostras) or unpack(amostras))

  if not esvaziando and m > LIMITE then
    filtro_normal = mp.get_property_native("vf")
    mp.set_property_native("vf", DRENO)
    esvaziando, amostras = true, {}
    mp.msg.info(string.format("fila de %.0f ms, esvaziando", m * 1000))
  elseif esvaziando and m < VOLTA then
    mp.set_property_native("vf", filtro_normal or {})
    esvaziando, amostras = false, {}
    mp.msg.info(string.format("fila esvaziada (%.0f ms)", m * 1000))
  end
end)
