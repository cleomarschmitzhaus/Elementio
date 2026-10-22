# Elementio — diagnosticos automaticos

Este diretorio guarda os relatorios gerados automaticamente pelo jogo e pelos testes.

## O que existe

| Arquivo | Quem gera | O que contem |
|---|---|---|
| `runtime_report.txt` | Autoload `ErrorReport` (ao fechar o jogo) | Relatorio da ultima execucao: checagens, autofixes, erros e avisos |
| `test_report.txt` | `tests/test_runner.tscn` | Resultado da suite de testes automatizados (PASS/FAIL) |
| `view_planet.png` | `tests/view_probe.tscn` | Screenshot da vista planeta |
| `view_surface.png` | `tests/view_probe.tscn` | Screenshot da vista superficie (Populous 3) |
| `view_sky.png` | `tests/view_probe.tscn` | Foco Local com o sol (e a lua) posicionados dentro da faixa de ceu |
| `view_surface_fov40.png` | `tests/view_probe.tscn` | Foco Local com FOV 40 (comparacao: o planeta vira uma "bola", ~66% de ceu) |
| `view_surface2.png` | `tests/view_probe.tscn` | Screenshot da vista superficie em outro ponto |
| `view_planet_max.png` | `tests/view_probe.tscn` | Zoom maximo da vista planeta (globo cobrindo a tela) |
| `view_pole.png` | `tests/view_probe.tscn` | Vista do polo (checa a emenda norte-sul do toro) |
| `view_boot_planet.png` / `view_boot_surface.png` | `tests/boot_probe.tscn` | Boot do jogo real: antes (vista planeta) e depois (Foco Local) |
| `view_blend_on.png` / `view_blend_off.png` | `tests/blend_probe.tscn` | A/B da mistura entre materiais (ligada x corte seco) |
| `view_blend_zoom_on.png` / `view_blend_zoom_off.png` | `tests/blend_probe.tscn` + recorte 3x | Detalhe ampliado da borda misturada x corte seco |
| `view_blend_zoom_on_045.png` / `view_blend_zoom_off_045.png` | idem, versao anterior | Mesmo recorte com a faixa antiga (`blend_width=0.045`) para comparar |

## Autodebug (em jogo)

O autoload `ErrorReport` (`scripts/debug/error_report.gd`) roda a cada 5 s e:

- verifica nos criticos (planeta, materiais/shaders, SubViewport, selecao, unidades, economia);
- **corrige automaticamente**: recria materiais ausentes, poda referencias liberadas na
  selecao, reativa SubViewport com render desligado, reseta unidades travadas, clampa
  economia negativa;
- escreve tudo em `user://logs/runtime.log` e em `docs/diagnostico/runtime_report.txt`;
- overlay **F3** mostra FPS, memoria, nº de checagens e autofixes.

## Testes automatizados

```powershell
# dentro da pasta do projeto
godot --headless --path . res://tests/test_runner.tscn
```

Ou use o atalho: `tools/run_tests.ps1`.
Sai com codigo 0 se tudo passa, 1 se houver falha. Resultado tambem em `test_report.txt`.

A suite headless tem **135 testes** (logica, sem GPU). O que so' o render mostra e'
coberto por **probes graficos** com janela real, que tambem saem com 0/1:
`tests/view_probe.tscn` (as duas vistas, o ceu **por pixel** — `SKY_PIXEL ...
ok=1`) e `tests/boot_probe.tscn` (o boot do jogo real).

## Relatorio de execucao do jogo

```powershell
# roda alguns segundos e captura erros do engine + autodebug
tools/run_game_report.ps1 -Seconds 10
```

## Vistas (Populous 3)

O planeta e' **topologicamente um toro** (como no Populous 3): o mapa repete nos
**dois eixos** (leste-oeste e norte-sul), sem borda, sem "disco" de espaco e sem
polo com corte. O plano e' **projetado localmente numa esfera** — e' isso que da'
a ilusao de planeta. Quem cruza uma borda reaparece na borda oposta (unidades,
construcoes e fontes), e o movimento usa o caminho mais curto atraves das
emendas (`PlanetTerrain.toroidal_delta`).

- **Vista planeta**: camera longe; WASD gira o planeta **somente no eixo vertical** —
  o norte fica sempre para cima e o globo **nunca inclina para os lados** (a
  orientacao N/S/L/O nao muda). O terreno e' a textura do
  SubViewport (8192x4096 = **1,02 texel por pixel de mundo**, pois o mundo agora
  e' 8000x4000), que cobre uma "volta" do mundo; as entidades fazem
  parte da textura, entao acompanham a rotacao. A luz e' a `DirectionalLight3D`
  da cena 3D (o planeta gira e passa pelo terminador dia/noite). Roda do mouse
  ajusta a distancia entre **1.10 (zoom maximo: o globo preenche a tela, sem
  espaco ao redor — medido por `SPACE_BORDA` no probe) e 5.0** (distancia padrao 2.2).
- **Vista superficie (Foco Local)**: camera **isometrica de cima** (inclinada ~65°,
  FOV 28) sobre o ponto focado. Tecla **V** ou botao da UI alterna. Na superficie a
  orientacao e' **NORTE FIXO** e a imagem **nunca gira**: **W/↑ sobe (norte)**,
  S/↓ desce, **A/← e D/→ andam para os lados** (sobre o paralelo, latitude fixa)
  e norte/sul andam sobre o meridiano. Como a vista olha a esfera **de fora**, a
  imagem e' **espelhada**: a direita da tela e' o **oeste** do mapa — e' isso que
  define o sinal de `move.x` em `_move_surface` (com o sinal errado, A/D ficam
  invertidos na tela). A orientacao e' **derivada do ponto focado**
  (`surface_north()` = +Y do mundo projetado no tangente; `surface_right()` = eixo
  leste-oeste), entao **nao ha rotacao acumulada/deriva** ao andar — no modo
  antigo a direcao era transportada em paralelo e a vista rodava ~6° numa
  caminhada em "L". O foco **para em ±88°**, porque o polo e' o ponto singular da
  bussola (a direcao "norte" deixa de existir exatamente em ±90°); `SURF_LAT_MAX`.
  Roda do mouse ajusta o zoom (distancia).

## Skybox procedural (ceu local + universo) e boot

Uma **unica** `Sky` com um `ShaderMaterial` (`shaders/sky.gdshader`) desenha as
duas vistas, misturadas pelo uniform `view_blend`:

- `view_blend = 1` (**Foco Local**): ceu azul com gradiente, **nuvens**
  procedurais (3 oitavas de ruido de valor) e os discos do **sol** e da **lua**.
- `view_blend = 0` (**Vista planeta**): **universo** — fundo quase preto, estrelas
  e uma nebula discreta.

Custo baixo por construcao: e' **um passe de tela cheia sem textura, sem
geometria e sem malha de nuvem** (so' matematica), a `Sky` usa o **radiance
cubemap minimo (32)** e modo **incremental** (`PROCESS_MODE_REALTIME` forcaria
radiance 256), e o ambiente continua usando **luz de cor** — o ceu **nao** entra
no GI/reflexo, e' so' o fundo. O fundo antes era uma cor escura fixa
(`background_mode = BG_COLOR`), agora e' `BG_SKY`.

O **sol e a lua orbitam** (`_update_sky` em `globe_main.gd`) em periodos
**diferentes** (150 s e 230 s), num plano orbital inclinado; as direcoes vao para
o shader (`sun_dir`/`moon_dir`) e a **`DirectionalLight3D` gira junto com o sol**,
entao a luz bate do lado onde o sol esta'. O "up" do ceu e' o radial do ponto
focado (`sky_up`), entao o horizonte e a projecao das nuvens ficam certos em
qualquer latitude.

> **Detalhe da vista de cima**: com a camera a ~65° e 2,2 raios de altura, o
> **horizonte** cai ~11° acima do centro do quadro — com o antigo **FOV 16** o ceu
> ficava **fora** do quadro. O **FOV foi para 28**: o terreno continua preenchendo
> o centro e o ceu (com sol e lua) ocupa **~44% da area** do quadro. O probe mede
> contando os raios da camera que **nao** batem na esfera: **`SURF_CEU
> area_total` = 0,437** (11,5% na coluna central; o resto e' o ceu que sobra nas
> laterais, ja' que a esfera nao cobre a largura toda). Valores para comparar:
> FOV 22 = 21%, FOV 28 = 44%, FOV 40 = 66% (`view_surface_fov40.png`). O ceu e' a
> faixa logo acima do horizonte da esfera, entao os astros aparecem quando estao
> **baixos** (como um nascer/por do sol visto de cima); a luz do terreno, porem,
> segue a orbita cheia.

O jogo **comeca na Vista Planeta e entra no Foco Local apos 2 s**
(`boot_to_surface` / `boot_delay`), e o boot posiciona o sol **alto** sobre o
ponto inicial para o ceu nascer iluminado. Testes e probes desligam o boot
(`boot_to_surface = false`) para controlar a vista manualmente. O probe
`tests/boot_probe.tscn` roda o **jogo real com o boot ligado** e confirma por
print + codigo de saida: `view_boot_planet.png` (universo/borda escura
`(2,2,7)`) e `view_boot_surface.png` (ceu azul + terreno).

O probe `tests/view_probe.tscn` confere o ceu **por pixel** (nao por opiniao):
le a imagem do viewport, converte de **linear para sRGB** (o viewport e' HDR; o
PNG salvo ja' e' sRGB) e exige que o centro do disco do **sol** seja bem mais
claro que o ceu ao lado, que o disco da **lua** seja frio/brilhante e que um
ponto neutro seja **azul** (bem mais azul que vermelho). Ele imprime `SKY_PIXEL
... sol_ok=1 lua_ok=1 ceu_ok=1` e **sai com codigo 1** se algum falhar
(`PROBE_DONE sky_check_ok=..`).

## Tamanho dos elementos, area do planeta e animacoes

- **Area do planeta 4x maior**: o mundo toroidal dobrou em cada eixo
  (4000x2000 -> **8000x4000**), mantendo o **mesmo tamanho de tile** (200 px de
  mundo) — por isso o planeta ganhou 40x20 tiles (era 20x10) e ficou mais
  fino/detalhado. As posicoes das entidades foram dobradas junto.
- **Elementos no tamanho ORIGINAL**: o efeito de "unidades e construcoes
  pequenas" vem da **area maior**, nao de encolher a arte. Skito/Spider/Mantis,
  Hollow Nest e fontes voltaram ao `scale` original (Skito 0.065, ninho 0.12,
  fonte 0.18), com colisao, anel de selecao, indicador e barras de status na
  mesma proporcao (barras 40x4 px na unidade carregada e 44x4 px no ninho/fonte,
  com separador de 1 px = 6 divisoes). Cada elemento passou a ocupar ~4x menos da
  superficie.
- **Animacoes 2x mais rapidas** por padrao: os frames trocam a 2 Hz (Skito/Mantis/
  Spider `ANIM_SPEED=2.0`, fonte `FRAME_INTERVAL=0.5`, ninho `ANIM_SPEED=2.0`).

## Transicoes entre materiais (tiles do terreno)

Cada material do terreno e' um tile de textura (agua, areia, terra, grama,
pedra). Antes o shader escolhia **um** deles por um `if` encadeado sobre a
elevacao, o que desenhava uma **linha de contorno nitida** entre os materiais
(cara de mapa pintado).

Agora os **mesmos tiles** sao pintados **em camadas**, de baixo para cima, com
uma faixa de `smoothstep` em cada limiar de elevacao: a agua e' o fundo e cada
material seguinte aparece por cima dissolvendo-se no anterior. Duas medidas
tornam a transicao natural:

1. **faixa de mistura** (`blend_width`, **largura TOTAL** da faixa em elevacao:
   hoje 0.03) — onde ela esta' a meio caminho, os dois tiles se misturam;
2. **serpenteio** (`edge_cells`/`edge_strength`) — um ruido suave de baixa
   frequencia desloca a curva de nivel no espaco do mundo, entao a fronteira
   avanca e recua como uma costa de verdade, em vez de seguir uma curva
   perfeita.

Largura medida da faixa: `largura = blend_width / |gradiente|`, com o gradiente
p50 medido **pelo proprio jogo** (teste `faixa de transicao ...` em
`tests/test_runner.gd`, 160x80 amostras perto do limiar da agua,
`|grad| p50 = 0,67 por 1000 px` de mundo):

| `blend_width` | faixa p50 (mundo) | em tiles (200 px) | na tela do Foco Local (0,59x, 640 px) |
|---|---|---|---|
| 0.045 (antiga) | 67 px | 0,33 tile | 40 px (6,2% da largura) |
| **0.03 (atual)** | **45 px** | **0,22 tile** | **27 px (4,2% da largura)** |
| 0.02 | 30 px | 0,15 tile | 18 px (2,8% da largura) |

O teste automatico guarda a faixa dentro de **0,05 a 0,60 tile** — assim um
futuro ajuste de `world_size` nao pode "lavar" os materiais sem aviso. O
serpenteio (`edge_strength = 0.018`) desloca a fronteira em ~±27 px, na mesma
escala da faixa, entao a borda fica irregular e suave ao mesmo tempo. As imagens
`view_blend_zoom_on/off_045.png` guardam o A/B da versao anterior
(`blend_width = 0.045`) para comparacao direta com as atuais.

Tudo isso usa **as texturas ja' existentes** (`assets/sprites/terrain_*.png`),
sem arte nova, e nao acrescenta nenhum `texture()` extra (o custo por fragmento
continua o mesmo: 5 tiles x 2 ladrilhamentos). Os parametros ficam exportados no
`PlanetTerrain` para ajuste no editor.

O `tests/blend_probe.tscn` gera um **A/B** (`view_blend_on.png` x
`view_blend_off.png`) e imprime `BLEND_AB ...`: a fracao de pixels que a mistura
muda e' exatamente a area das bordas — se a transicao fosse um degrau, as duas
imagens seriam identicas.

### Emenda do toro (ruido periodico)

O ruido que gera o relevo passou a ser **periodico** (`hash_periodic`,
`noise_periodic`, `fbm_periodic` no shader e `_hash_periodic`, `_noise`,
`_fbm` no `planet_terrain.gd`). Antes ele **nao fechava na emenda** do toro:
como o `fract(world_px / world_size)` da' a volta em **x=0 e y=0** (no meio do
mundo jogavel, nao nas bordas), a elevacao saltava ~0,15 de um pixel para o
outro e aparecia uma **linha reta de material** cortando o planeta. Agora o
degrau maximo medido na emenda e' ~0,0003. O teste `emenda X em x=0 ...` cobre
isso (o teste antigo comparava +-world_size/2, onde o `fract` da' o mesmo valor
por construcao, e nao pegava nada).

## Qualidade dos sprites / texturas

Como os sprites (arte de 512px por quadro) ocupam ~33px de mundo e a vista de
Foco Local mostra ~1,02 texel por pixel de mundo (medido pelo probe,
`SURF_SPAN ... texels_por_pixel_mundo`; com o FOV 28 o mundo aparece a ~0,59x na
tela), duas medidas evitam o aspecto "quadriculado":
os spritesheets e os tiles de terreno sao importados **com mipmaps**
(`mipmaps/generate=true`) e todo canvas 2D usa **filtro linear com mipmap**
(`rendering/textures/canvas_textures/default_texture_filter=3`). A textura do
planeta tambem usa filtro linear com mipmap (antes era NEAREST, que deixava os
blocos visiveis ao ampliar). O probe `tests/view_probe.gd` imprime a
magnificacao real da vista local (`SURF_SPAN ... magnificacao=..x`).

## Arte fornecida pelo usuario (substituicao do Mantis)

A arte do **Mantis** (`assets/sprites/mantis_sheet.png`) foi substituida por uma
versao nova fornecida pelo usuario (Photoroom, fundo removido), com o mesmo
layout dos outros insetos: spritesheet **2x2 / 4 quadros de 512x512**
(`hframes=2`, `vframes=2`), 1024x1024, mipmaps gerados. O `scale` do
`Sprite2D` (0.07) e os frames usados pelo `unit.gd` (0-1 caminhada/voo,
2-3 colheita/ataque) permanecem validos, e a escala efetiva continua
**35.84 px de mundo** (teste `[8]` "Arte dos elementos" PASS). Suite de testes
headless segue **135 PASS / 0 FAIL**. A versao anterior foi preservada em
`%TEMP%/opencode/elementio_backup/mantis_sheet_anterior.png` (backup local, fora
do repositorio). Verificacao visual: `docs/diagnostico/mantis_novo_frames.png`.

