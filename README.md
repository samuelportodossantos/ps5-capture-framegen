# ps5-capture-framegen

Jogue o PS5 (ou outro console) pela placa de captura no **Linux**, com **frame gen** (30 → 120 fps), baixa latência e áudio, numa janela fixa da tela, ligando tudo com um comando: `ps5`.

> **EN:** One-command console capture viewer for Linux: mpv (Vulkan, low-latency, duplicate-frame removal) + [lsfg-vk](https://lsfg-vk.dev) frame generation (Lossless Scaling) + PipeWire audio loopback + a KDE window rule. Turns a 30 fps console game into 120 fps on screen.

```
console ──HDMI 60 Hz──▶ placa USB 3 ──30 fps──▶ mpv (Vulkan, --untimed) ──▶ lsfg-vk x4 ──▶ tela 120 Hz
                            │                  + drain.lua (esvazia fila)    30 → 120
                            └── áudio ──▶ pw-loopback (20 ms) ──▶ saída padrão
```

## O que precisa

- Linux com **Vulkan** e **PipeWire**. Testado no Ubuntu 26.04, KDE Plasma 6.6 (Wayland), RTX 2060 com driver NVIDIA 580.
- **Placa de captura UVC numa porta USB 3**. Testado com MacroSilicon MS2130 (`345f:2131`), que entrega 1080p60 em YUYV.
- **[Lossless Scaling](https://store.steampowered.com/app/993090/Lossless_Scaling/) comprado na Steam**, no branch `lsfg-vk`. O frame gen usa os shaders dele. Ele é pago e não vem neste repositório.
- Monitor de **120 Hz ou mais**, para o frame gen ter efeito.
- Opcional: **KDE Plasma 6**, para a regra que fixa a janela. Em outros ambientes tudo funciona, mas a janela abre onde o compositor quiser.

## Instalar

```bash
sudo apt install mpv pipewire-bin pulseaudio-utils curl xz-utils   # Ubuntu/Debian
```

Na Steam: **Lossless Scaling → Propriedades → Betas → `lsfg-vk`**, e espere atualizar. Depois:

```bash
git clone https://github.com/samuelportodossantos/ps5-capture-framegen
cd ps5-capture-framegen
./install.sh                          # janela na metade esquerda do monitor
./install.sh --janela 1920x1080+0+0   # ou tamanho e posição à sua escolha
```

O instalador não usa sudo. Ele:
1. baixa o **lsfg-vk 2.0.0** do site oficial, confere o SHA-256 e instala em `~/.local`;
2. acha o `lsfg-vk.dll` da Steam (nativa, Flatpak ou Snap, inclusive em outras bibliotecas);
3. cria o perfil `ps5-capture` em `~/.config/lsfg-vk/conf.toml`. Se o arquivo já existir, faz um backup e acrescenta o perfil;
4. instala o comando `ps5` em `~/.local/bin`;
5. cria a regra de janela do KDE: posição e tamanho fixos, sem borda e acima dos painéis.

Rodar de novo é seguro, porque o que já existe é mantido. Para desinstalar: `./uninstall.sh`. Ele deixa o lsfg-vk instalado; para tirar também, rode `rm ~/.local/bin/lsfg-vk-* ~/.local/lib/liblsfg-vk-layer* ~/.local/share/vulkan/implicit_layer.d/VkLayer_LSFGVK_*`.

## Usar

```
ps5            liga (se já estiver ligada, desliga)
ps5 off        desliga
ps5 sem-fg     liga sem frame gen, para comparar
ps5 fg 2|3|4   muda o multiplicador (jogo a 30: 60, 90 ou 120 fps)
ps5 status     mostra o que está rodando
```

Na janela, **q** fecha. Para depurar, `PS5_LOG=/tmp/ps5.log ps5` grava o log do mpv, incluindo o que o vigia de fila fez.

Se a sua placa não for MacroSilicon, ajuste `~/.config/ps5-capture/config`. Veja os nomes com `ls /dev/v4l/by-id/` e `pactl list sources short`.

## Por que cada peça existe

Cada item abaixo resolveu um problema que foi **medido**, não suposto.

| Problema | Sintoma | Solução |
|---|---|---|
| Placa negociando **USB 2.0**, mesmo em porta azul | imagem ruim; YUYV 1080p60 não cabe em 480 Mbps | ligar direto numa porta USB 3 e conferir com `lsusb -t` (tem que aparecer `5000M`) |
| mpv tratando a captura como vídeo comum | **atraso crescente** (o buffer foi de 0,48 s a 0,75 s em 8 s) e trancos | `--untimed --cache=no --demuxer-readahead-secs=0`: o buffer cai para 1 quadro (~17 ms) |
| Jogo a **30 fps** numa saída de **60 Hz** | cada quadro chega 2 vezes, e o frame gen "interpola" entre quadros iguais | pedir **30 fps à placa** (`VIDEO_FPS=30`): 149 de 150 quadros vêm únicos |
| lsfg-vk em V-Sync **bloqueia**: em x4 a 120 Hz o mpv consome exatamente 30 quadros/s | no menu do PS5 (60 únicos) a fila chegou a **~1 s**. Como depois entra o mesmo tanto que sai, **a fila nunca esvazia**, e já começa com ~0,9 s porque o mpv demora para iniciar | entrada fixa de 30 (x4 = 120 Hz) e **`drain.lua`**: mede o atraso real (o horário dos quadros é o relógio monotônico do kernel) e, quando passa de 80 ms, descarta quadros até esvaziar. Resultado: **~48 ms estável**, e uma fila forçada some em ~1,5 s |
| Tentativa: lsfg-vk em mailbox, sem bloquear | atraso caiu para 26 ms, **mas o jogo parecia 30 fps**, porque os quadros gerados eram descartados | descartada: FIFO + `drain.lua` |
| `Lossless.dll` do branch normal da Steam | `Unable to find base shader 'mipmaps' in DLL` | branch **`lsfg-vk`** → `lsfg-vk.dll` |
| Áudio dentro do mpv | o modo `--untimed` não sincroniza som | `pw-loopback` da entrada da placa para a saída padrão, com 20 ms |
| Frame gen ligado em todo mpv | a camada Vulkan é implícita (carrega em qualquer app) | perfil ativado só por `LSFGVK_PROFILE`, que apenas o `ps5` define |
| mpv com lsfg-vk **travando ao fechar** (intermitente; visto com driver NVIDIA, mais quando aberto via systemd) | janela congelada | `q` e `ps5 off` encerram com `kill -9`. O mpv só exibe, não há nada a salvar |
| `/dev/videoN` mudando depois de reiniciar | abre a webcam no lugar da placa | a placa é achada por `/dev/v4l/by-id/` |

Benchmark do lsfg-vk numa RTX 2060, 1080p com x4: **806 fps de saída** (`lsfg-vk-cli benchmark -w 1920 -h 1080 -m 4`). Para 30 → 120 sobra muita folga.

## Limitações

- O frame gen não diminui o atraso do controle: ele continua sendo o de 30 fps, um pouco maior por causa do V-Sync que o lsfg-vk força e do quadro que ele segura. Para jogo competitivo, prefira jogar direto na TV.
- Partindo de 30 fps, aparecem **artefatos** em movimento rápido, em volta do personagem e no HUD. O `ps5 fg 2` gera menos artefato, mas só chega a 60.
- **O DLSS não funciona aqui.** Ele precisa de dados do motor do jogo (vetores de movimento, profundidade), que não existem num vídeo capturado. O frame gen do Lossless Scaling trabalha só com a imagem.
- O FPS que realmente chega à tela não foi medido com contador. Para conferir, use MangoHud ou similar.
- Os ~48 ms medidos são só o caminho **dentro do PC** (da captura até o mpv). Não incluem o atraso da placa, o do frame gen depois do mpv nem o do monitor.
- A conta precisa fechar: **`VIDEO_FPS` × multiplicador = Hz do monitor**. Jogo a 60 fps? Use `VIDEO_FPS=60` e `ps5 fg 2`. Monitor de 144 Hz não fecha com 30; deixe o monitor em 120 Hz.

## Créditos e licenças

- [lsfg-vk](https://lsfg-vk.dev), de PancakeTAS (CC BY-NC-ND 4.0): baixado pelo instalador, não redistribuído aqui.
- [Lossless Scaling](https://store.steampowered.com/app/993090/Lossless_Scaling/), de THS: necessário comprar.
- [mpv](https://mpv.io), [PipeWire](https://pipewire.org).

Os scripts deste repositório estão sob a licença [MIT](LICENSE).
