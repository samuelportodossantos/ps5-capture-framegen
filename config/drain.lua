-- Esvazia a fila da placa de captura quando o atraso cresce.
--
-- Com o lsfg-vk em V-Sync (FIFO), cada quadro do mpv vira N quadros na tela e a apresentação BLOQUEIA:
-- em x4 a 120 Hz o mpv consome exatamente 30 quadros/s. Qualquer fila que se forme (o mpv leva ~1 s
-- para iniciar o Vulkan enquanto a placa já captura; engasgo do compositor ao trocar o foco; engasgo
-- do driver) fica presa para sempre, porque entra o mesmo tanto que sai.
--
-- Como detecta:
--   * ENTRAR: o horário de cada quadro (time-pos) vem do relógio do kernel na captura, então
--     mp.get_time() - time-pos = atraso + uma constante desconhecida. Ao sair de um esvaziamento a fila
--     está vazia: o menor valor da janela nessa hora vira a BASE. Se o menor valor da janela (~0,5 s)
--     passar de BASE + MARGEM, há fila. (Usa o menor: um quadro parado na tela envelhece sem haver fila.)
--   * SAIR: esvaziando, o mpv lê 4 quadros para cada 1 mostrado. Enquanto há fila, o vídeo avança bem
--     mais rápido que o relógio (>2x). Avançando no ritmo do relógio (~1x), a fila acabou.
--     Não depende de acertar relógios: a versão anterior saía por atraso absoluto < 50 ms, o acerto de
--     relógio errava ~20 ms para cima e o esvaziamento ficava preso (1 de 4 quadros = jogo a ~7 fps).

local MARGEM = 0.045  -- s acima da base = há fila (1 quadro de 30 fps = 33 ms; a fase varia até isso)
local RITMO  = 1.5    -- esvaziando, avanço do vídeo / relógio abaixo disso = fila vazia
local JANELA = 16     -- amostras (x 1/30 s ~ 0,5 s)
local DRENO  = { { name = "lavfi", params = { graph = "framestep=4" } } }

local base, amostras, esvaziando, filtro_normal = nil, {}, false, nil

local function esvaziar(motivo)
  filtro_normal = mp.get_property_native("vf")
  mp.set_property_native("vf", DRENO)
  esvaziando, amostras = true, {}
  mp.msg.info("esvaziando: " .. motivo)
end

-- Começa já esvaziando: enquanto o mpv inicia, a placa enche a fila (medido: ~0,9 s na partida).
esvaziar("partida")

mp.add_periodic_timer(1 / 30, function()
  local tp = mp.get_property_number("time-pos")
  if not tp then return end
  local agora = mp.get_time()
  local ult = amostras[#amostras]
  if ult and (tp < ult.tp or tp - ult.tp > 5) then amostras = {} end   -- salto no horário: recomeça
  amostras[#amostras + 1] = { t = agora, tp = tp, d = agora - tp }
  if #amostras > JANELA then table.remove(amostras, 1) end
  if #amostras < JANELA then return end

  local m = math.huge
  for _, a in ipairs(amostras) do if a.d < m then m = a.d end end

  if esvaziando then
    local p, u = amostras[1], amostras[#amostras]
    local ritmo = (u.tp - p.tp) / (u.t - p.t)
    if ritmo < RITMO then
      mp.set_property_native("vf", filtro_normal or {})
      local antes = base
      base, esvaziando, amostras = m, false, {}
      mp.msg.info(string.format("fila esvaziada (ritmo %.2fx; base %s)", ritmo,
        antes and string.format("%+.0f ms", (m - antes) * 1000) or "nova"))
    end
  else
    if m < base then base = m end                 -- a fase entre placa e tela deriva: segue o menor
    if m > base + MARGEM then
      esvaziar(string.format("fila de ~%.0f ms acima do normal", (m - base) * 1000))
    end
  end
end)
