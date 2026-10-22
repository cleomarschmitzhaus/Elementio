shader_type sky;

// ===========================================================================
// SKYBOX "INTELIGENTE" do Elementio — 100% procedural.
//
// Custo: UM passe de tela cheia, so' matematica (sem textura, sem geometria,
// sem malha de nuvem, sem cubemap caro). O `Sky.radiance_size` fica no minimo
// (32) e o ambiente usa luz de COR (nao usa o ceu para GI), entao o ceu nao
// alimenta reflexo/iluminacao indireta: e' so' o fundo.
//
// Um unico shader desenha as DUAS vistas, misturadas por `view_blend`:
//   view_blend = 0 -> UNIVERSO (vista planeta): estrelas + nebula
//   view_blend = 1 -> CEU      (Foco Local): azul + nuvens + sol + lua
//
// O sol e a lua ORBITAM: as direcoes chegam do globe_main.gd (sun_dir/moon_dir
// em periodos DIFERENTES), que tambem gira a DirectionalLight3D para a luz
// bater do lado onde o sol esta'.
//
// O "up" do ceu e' o radial do ponto focado (sky_up), entao o horizonte e as
// nuvens ficam sempre certos, em qualquer latitude.
// ===========================================================================

uniform float view_blend : hint_range(0.0, 1.0) = 1.0;
uniform vec3 sky_up = vec3(0.0, 0.0, 1.0);
uniform vec3 sky_north = vec3(0.0, 1.0, 0.0);
uniform vec3 sky_right = vec3(-1.0, 0.0, 0.0);
uniform vec3 sun_dir = vec3(0.0, 0.45, 1.0);
uniform vec3 moon_dir = vec3(0.0, -0.3, -1.0);
uniform float sky_time = 0.0;
uniform float cloud_amount : hint_range(0.0, 1.0) = 0.55;
uniform float sun_size : hint_range(0.9, 0.9999) = 0.99920;
uniform float moon_size : hint_range(0.9, 0.9999) = 0.99910;

// ceu da superficie
uniform vec4 zenith_color : source_color = vec4(0.11, 0.33, 0.70, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.70, 0.85, 0.99, 1.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.94, 0.74, 1.0);
uniform vec4 moon_color : source_color = vec4(0.84, 0.87, 0.97, 1.0);
uniform vec4 cloud_light : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 cloud_dark : source_color = vec4(0.58, 0.64, 0.76, 1.0);

// universo (vista planeta)
uniform vec4 space_color : source_color = vec4(0.008, 0.010, 0.028, 1.0);
uniform vec4 nebula_color : source_color = vec4(0.16, 0.20, 0.48, 1.0);

float hash13(vec3 p3) {
    p3 = fract(p3 * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ruido de valor 2D (barato: 4 hashes por oitava)
float noise2(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = hash13(vec3(i, 0.0));
    float b = hash13(vec3(i + vec2(1.0, 0.0), 0.0));
    float c = hash13(vec3(i + vec2(0.0, 1.0), 0.0));
    float d = hash13(vec3(i + vec2(1.0, 1.0), 0.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 3 oitavas -> nuvens com forma, custo baixo
float cloud_field(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 3; i++) {
        v += a * noise2(p);
        p = p * 2.07 + vec2(3.1, 1.7);
        a *= 0.5;
    }
    return v;
}

// estrelas esparsas: 1 celula de direcao -> ~1 ponto ocasional
vec3 star_field(vec3 dir) {
    vec3 cell = floor(dir * 190.0);
    vec3 f = fract(dir * 190.0);
    float h = hash13(cell);
    vec3 rnd = vec3(hash13(cell + 17.0), hash13(cell + 31.0), hash13(cell + 47.0));
    float d = length(f - rnd);
    float s = step(0.9956, h) * smoothstep(0.30, 0.0, d);
    float tw = 0.6 + 0.4 * sin(sky_time * 2.5 + h * 70.0);
    return vec3(s * tw);
}

vec3 space_sky(vec3 dir) {
    // nebula suave (2 oitavas, bem discreta) para o fundo nao ficar chato
    float n = cloud_field(dir.xy * 1.1 + dir.z * 0.9);
    vec3 col = space_color.rgb + nebula_color.rgb * smoothstep(0.62, 1.0, n) * 0.35;
    return col + star_field(dir);
}

vec3 local_sky(vec3 dir, vec3 up, vec3 north, vec3 right) {
    float el = dot(dir, up);
    vec3 sd = normalize(sun_dir);
    vec3 md = normalize(moon_dir);

    // Dia/noite SUAVE: o ceu nunca fica preto (o sol/lua podem aparecer baixos),
    // so' escurece um pouco quando o sol esta' do outro lado.
    float sun_elev = dot(sd, up);
    float day = clamp(sun_elev * 0.9 + 0.62, 0.55, 1.0);

    // A faixa de ceu visivel no Foco Local fica logo ACIMA do horizonte da
    // esfera, que cai em el ~ -0.7..-0.9. O gradiente e' mapeado nessa faixa
    // (zenite no el baixo/afastado, horizonte no el alto/perto da borda).
    float t = smoothstep(-0.98, 0.02, el);
    vec3 col = mix(zenith_color.rgb, horizon_color.rgb, t) * day;

    // nuvens: projetadas no "plano" de nuvens (perspectiva converge no horizonte)
    vec2 cc = vec2(dot(dir, right), dot(dir, north)) / max(el, 0.10) * 0.45;
    float thresh = mix(0.86, 0.42, cloud_amount);
    float cov = smoothstep(thresh, thresh + 0.22, cloud_field(cc + vec2(sky_time * 0.010, sky_time * 0.004)));
    cov *= smoothstep(0.02, 0.22, el);   // some no horizonte
    vec3 cloud_col = mix(cloud_dark.rgb, cloud_light.rgb, day * 0.85 + 0.15);
    col = mix(col, cloud_col * day, cov);

    // sol: disco + brilho
    float sdot = dot(dir, sd);
    float sun_disk = smoothstep(sun_size, sun_size + 0.0004, sdot);
    float sun_glow = pow(max(sdot, 0.0), 240.0) * 0.7 + pow(max(sdot, 0.0), 14.0) * 0.16;
    col += sun_color.rgb * (sun_disk * 1.1 + sun_glow);

    // lua: disco (mais frio) + halo leve
    float mdot = dot(dir, md);
    float moon_disk = smoothstep(moon_size, moon_size + 0.0004, mdot);
    float moon_glow = pow(max(mdot, 0.0), 320.0) * 0.35;
    col += moon_color.rgb * (moon_disk * 0.9 + moon_glow);

    return col;
}

void sky() {
    vec3 dir = EYEDIR;
    vec3 space = space_sky(dir);
    vec3 local = local_sky(dir, normalize(sky_up), normalize(sky_north), normalize(sky_right));
    COLOR = mix(space, local, clamp(view_blend, 0.0, 1.0));
}
