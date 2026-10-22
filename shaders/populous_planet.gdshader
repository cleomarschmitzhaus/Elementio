shader_type canvas_item;

// Parametros do Planeta (estilo Populous 3) - terreno estilo Factorio
uniform float planet_radius : hint_range(0.2, 1.0) = 0.48;
uniform float planet_radius_world = 960.0;
uniform vec2 camera_offset = vec2(0.0);
uniform vec2 world_size = vec2(8000.0, 4000.0);
uniform vec2 rect_size = vec2(10400.0);
uniform vec4 space_color : source_color = vec4(0.02, 0.03, 0.06, 1.0);
uniform vec4 atmosphere_color : source_color = vec4(0.2, 0.55, 0.85, 0.4);

// ---------------------------------------------------------------------------
// Tiles do terreno (um por material, nitidos e sem emenda). repeat_enable faz
// o ladrilhamento continuo. Inspirados no terreno do Factorio: base oliva /
// khaki quente, moitas verde-escuras, areia clara, pedra cinza e agua teal.
// ---------------------------------------------------------------------------
uniform sampler2D tex_water : repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_sand  : repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_dirt  : repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_grass : repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_rock  : repeat_enable, filter_linear_mipmap;

// 1/200 = um tile a cada 200 px de mundo (mundo 8000x4000 -> 40x20 tiles).
uniform float tile_scale = 0.005;
uniform float detail_mix : hint_range(0.0, 1.0) = 0.45;
uniform float tex_brightness : hint_range(0.0, 2.0) = 1.0;
uniform float tex_contrast : hint_range(0.0, 2.0) = 1.0;
// Granulado das bordas entre materiais (dither no espaco do mundo)
uniform float dither_amount : hint_range(0.0, 0.04) = 0.010;

// ---------------------------------------------------------------------------
// MISTURA ENTRE MATERIAIS (transicoes naturais entre os tiles)
// ---------------------------------------------------------------------------
// Antes cada material era escolhido por um "if" (corte seco): a troca
// agua -> areia -> terra -> grama -> rocha desenhava uma linha de contorno
// nitida, com cara de mapa pintado.
// Agora os MESMOS tiles sao pintados EM CAMADAS, um sobre o outro, com uma
// faixa de smoothstep em cada limiar de elevacao: cada material se dissolve
// dentro do seguinte. As duas ultimas constantes "serpenteiam" essa faixa com
// ruido de baixa frequencia, entao a fronteira avanca e recua como uma costa
// de verdade, em vez de seguir uma curva de nivel perfeita.
uniform float blend_width : hint_range(0.0, 0.15) = 0.03;    // largura da faixa de mistura
uniform float edge_cells = 36.0;                              // celulas de ruido do serpenteio no mundo
uniform float edge_strength : hint_range(0.0, 0.15) = 0.018;  // amplitude do serpenteio

// ---------------------------------------------------------------------------
// IMPORTANTE: hash/noise/fbm/elevacao abaixo devem ser IDENTICOS aos de
// scripts/planet_terrain.gd. Assim o que se VE na tela e exatamente o mesmo
// que a logica de caminhada/construcao usa (unidades nunca "descolam" do chao).
// ---------------------------------------------------------------------------
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Ruido de valor PERIODICO: o reticulado e' dobrado modulo `period`, entao o
// campo se repete exatamente a cada `period` celulas. Sem isto o ruido nao
// fechava na emenda do toro (x=0 / y=0) e aparecia uma LINHA RETA de material
// no meio do planeta (a elevacao saltava ~0.15 de um pixel para o outro).
float hash_periodic(vec2 p, vec2 period) {
    return hash(mod(p, period));
}

float noise_periodic(vec2 p, vec2 period) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash_periodic(i + vec2(0.0, 0.0), period), hash_periodic(i + vec2(1.0, 0.0), period), u.x),
               mix(hash_periodic(i + vec2(0.0, 1.0), period), hash_periodic(i + vec2(1.0, 1.0), period), u.x), u.y);
}

// fbm periodico: a cada oitava a frequencia dobra e o periodo dobra junto; o
// deslocamento por oitava e' um inteiro, portanto nao quebra a periodicidade.
float fbm_periodic(vec2 p, vec2 period) {
    float v = 0.0;
    float a = 0.5;
    vec2 q = p;
    vec2 per = period;
    for (int i = 0; i < 4; ++i) {
        v += a * noise_periodic(q + vec2(float(i) * 3.0 + 1.0, float(i) * 5.0 + 2.0), per);
        q *= 2.0;
        per *= 2.0;
        a *= 0.5;
    }
    return v;
}

float terrain_elevation(vec2 norm_uv) {
    vec2 p = norm_uv * 6.2831853;
    float e = sin(p.x) * cos(p.y) * 0.35
            + fbm_periodic(norm_uv * 12.0, vec2(12.0)) * 0.45
            + fbm_periodic(norm_uv * 24.0, vec2(24.0)) * 0.20;
    return clamp(e, 0.0, 1.0);
}

// Ajuste simples de brilho/contraste da textura do tile
vec3 grade(vec3 c) {
    return clamp((c - vec3(0.5)) * tex_contrast + vec3(0.5), vec3(0.0), vec3(1.0)) * tex_brightness;
}

// ---------------------------------------------------------------------------
// Faixas de material. L_WATER e L_ROCK casam com as constantes de
// scripts/planet_terrain.gd (WATER_THRESHOLD / CLIFF_THRESHOLD): sao elas que
// decidem onde da' pra andar e construir. L_SAND e L_DIRT sao so' estetica.
// ---------------------------------------------------------------------------
const float L_WATER = 0.38;
const float L_SAND  = 0.42;
const float L_DIRT  = 0.47;
const float L_ROCK  = 0.68;

// Cor do terreno para uma dada elevacao (ja' com o granulado e o serpenteio
// aplicados). Os cinco materiais entram EM CAMADAS, de baixo para cima: a agua
// e' o fundo e cada material seguinte aparece por cima com uma faixa de
// smoothstep no seu proprio limiar. Onde a faixa esta' a meio caminho os dois
// tiles se misturam, entao a troca e' uma dissolucao e nao um corte.
// O segundo ladrilhamento (uv2) entra depois, misturado, para disfarcar a
// repeticao do padrao sem borrar o tile.
vec3 terrain_color_at(float e, vec2 uv, float shore) {
    vec3 c_water = grade(texture(tex_water, uv).rgb);
    vec3 c_sand  = grade(texture(tex_sand,  uv).rgb);
    vec3 c_dirt  = grade(texture(tex_dirt,  uv).rgb);
    vec3 c_grass = grade(texture(tex_grass, uv).rgb);
    vec3 c_rock  = grade(texture(tex_rock,  uv).rgb);

    // agua rasa clareia perto da praia
    c_water = mix(c_water, c_water * 1.45 + vec3(0.03, 0.08, 0.08), shore * 0.8);

    float hw = blend_width * 0.5;
    float w_sand  = smoothstep(L_WATER - hw, L_WATER + hw, e);
    float w_dirt  = smoothstep(L_SAND  - hw, L_SAND  + hw, e);
    float w_grass = smoothstep(L_DIRT  - hw, L_DIRT  + hw, e);
    float w_rock  = smoothstep(L_ROCK  - hw * 1.4, L_ROCK + hw * 1.4, e);

    vec3 c = c_water;
    c = mix(c, c_sand,  w_sand);
    c = mix(c, c_dirt,  w_dirt);
    c = mix(c, c_grass, w_grass);
    c = mix(c, c_rock,  w_rock);
    return c;
}

void fragment() {
    // Posicao no mundo (em pixels), 1:1 com as coordenadas das unidades e
    // construcoes. Sem distorcao esferica nos UVs do terreno: assim o sprite
    // continua exatamente sobre o mesmo pixel do chao em qualquer posicao da
    // camera.
    vec2 world_px = camera_offset + (UV - vec2(0.5)) * rect_size;

    vec2 norm_uv = fract(world_px / world_size);
    float elevation = terrain_elevation(norm_uv);

    // Granulado: desloca a elevacao por um valor fixo por pixel de MUNDO
    // (nao pisca quando a camera anda). E' o que da' a borda "serrilhada"
    // no nivel do pixel, tirando o aspecto de vetor.
    float dith = (hash(floor(world_px)) - 0.5) * dither_amount;

    // Serpenteio: ruido suave (2 oitavas) deslocando a curva de nivel. Fica no
    // espaco NORMALIZADO (periodico) para nao criar emenda no toro.
    vec2 wob_uv = norm_uv * edge_cells;
    float wob = noise_periodic(wob_uv, vec2(edge_cells)) * 0.66
              + noise_periodic(wob_uv * 2.0 + vec2(7.0, 3.0), vec2(edge_cells * 2.0)) * 0.34;
    wob = (wob - 0.5) * 2.0 * edge_strength;

    float e = clamp(elevation + dith + wob, 0.0, 1.0);
    float shore = smoothstep(L_WATER - 0.05, L_WATER, elevation);

    // Dois ladrilhamentos (um girado) para disfarcar a repeticao
    vec2 uv1 = world_px * tile_scale;
    float cs = cos(0.7); float sn = sin(0.7);
    vec2 uv2 = mat2(vec2(cs, -sn), vec2(sn, cs)) * (world_px * tile_scale * 1.97) + vec2(0.37, 0.61);

    vec3 c1 = terrain_color_at(e, uv1, shore);
    vec3 c2 = terrain_color_at(e, uv2, shore);
    vec3 terrain_color = mix(c1, c2, detail_mix);

    // Planeta-TORO (Populous 3): o mapa repete nos DOIS eixos (o fract em
    // world_px / world_size), entao nao existe borda, "disco" de espaco nem
    // polo com corte. Ao dar a volta (leste-oeste OU norte-sul) o terreno
    // continua exatamente de onde parou, sem emenda.
    // A luz nao e' mais "ancorada no mundo": quem sombreia a esfera e' a
    // DirectionalLight3D da cena 3D (luz real conforme o planeta gira).
    // Aqui sai apenas a albedo do terreno; as entidades entram no mesmo
    // SubViewport e sao sombreadas pela mesma luz.
    COLOR = vec4(terrain_color, 1.0);
}
